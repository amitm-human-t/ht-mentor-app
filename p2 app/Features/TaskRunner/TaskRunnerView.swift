import SwiftUI
import UIKit

struct TaskRunnerView: View {
    let appModel: AppModel
    private let runnerCoordinator: RunnerCoordinator
    private let debugVideoFrameSource: DebugVideoFrameSource
    let taskDefinition: TaskDefinition

    @State private var selectedMode: TaskMode = .guided
    @State private var isControlPanelVisible = true
    @State private var runResultsShown = false
    @State private var showExitConfirmation = false
    @State private var mediumFeedback = UIImpactFeedbackGenerator(style: .medium)
    @State private var lightFeedback = UIImpactFeedbackGenerator(style: .light)
    @Environment(\.dismiss) private var dismiss

    init(appModel: AppModel, taskDefinition: TaskDefinition) {
        self.appModel = appModel
        self.taskDefinition = taskDefinition
        self.runnerCoordinator = appModel.runnerCoordinator
        self.debugVideoFrameSource = appModel.debugVideoFrameSource
    }

    var body: some View {
        VStack(spacing: 0) {
            // HUD strip
            RunnerHUDView(coordinator: runnerCoordinator)

            // Camera + optional trailing panel
            HStack(spacing: 0) {
                cameraArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isControlPanelVisible {
                    Rectangle()
                        .fill(Color.hxSurfaceBorder)
                        .frame(width: 1)
                        .ignoresSafeArea()

                    TrainerControlsPanel(
                        appModel: appModel,
                        taskDefinition: taskDefinition,
                        selectedMode: $selectedMode,
                        isVisible: $isControlPanelVisible
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // Bottom action bar
            bottomBar
        }
        .background(Color.hxBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .animation(.hxPanel, value: isControlPanelVisible)
        .task {
            mediumFeedback.prepare()
            lightFeedback.prepare()
            if runnerCoordinator.activeTask?.id != taskDefinition.id {
                let preferredMode = taskDefinition.supportedModes.contains(.guided)
                    ? TaskMode.guided
                    : taskDefinition.supportedModes.first ?? .manual
                selectedMode = preferredMode
                runnerCoordinator.prepare(task: taskDefinition, mode: preferredMode)
            }
            await runnerCoordinator.beginPreviewInference()
        }
        .onDisappear {
            // Only persist here if we haven't already done so via the Results button
            if !runResultsShown,
               let summary = runnerCoordinator.buildSummary(),
               runnerCoordinator.stateMachine.phase == .finished {
                appModel.persistCompletedRun(summary: summary)
            }
        }
        .overlay {
            if let countdown = runnerCoordinator.disconnectCountdown {
                BLEReconnectOverlay(countdown: countdown) {
                    runnerCoordinator.finish()
                }
                .animation(.hxModal, value: countdown)
            }
        }
        .confirmationDialog(
            "End task and return to Hub?",
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Task", role: .destructive) {
                endTaskAndReturnToHub()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will end the current task and release task resources.")
        }
    }

    // MARK: - Camera Area

    private var cameraArea: some View {
        ZStack {
            AppPreviewStageView(appModel: appModel, showsControls: false, compact: false)
                .ignoresSafeArea()

            // Failure banner (non-blocking, semi-transparent)
            if let failure = runnerCoordinator.currentFailure {
                VStack {
                    HStack(spacing: HXSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.hxDanger)
                        Text(failure.localizedDescription ?? "Error")
                            .font(.hxCallout)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, HXSpacing.lg)
                    .padding(.vertical, HXSpacing.sm)
                    .background(Color.hxDanger.opacity(0.20), in: Capsule())
                    .padding(.top, HXSpacing.xl)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.hxDefault, value: runnerCoordinator.currentFailure != nil)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: HXSpacing.lg) {
            let phase = runnerCoordinator.stateMachine.phase

            // Back button — only when not actively running
            if phase == .idle || phase == .finished || phase == .error {
                Button {
                    showExitConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.callout.weight(.semibold))
                        Text(phase == .finished ? "Done" : "Tasks")
                            .font(.hxCallout)
                    }
                    .foregroundStyle(Color.hxCyan)
                }
                .buttonStyle(.plain)
            }

            // Controls toggle
            Button {
                withAnimation(.hxPanel) {
                    isControlPanelVisible.toggle()
                }
            } label: {
                Label(
                    isControlPanelVisible ? "Hide Controls" : "Controls",
                    systemImage: "slider.horizontal.3"
                )
                .font(.hxCallout)
            }
            .buttonStyle(.glass)

            Spacer()

            // Primary run control
            if phase == .idle || phase == .error {
                Button {
                    mediumFeedback.impactOccurred()
                    Task { await runnerCoordinator.start() }
                } label: {
                    Group {
                        if runnerCoordinator.isModelLoading {
                            HStack(spacing: 6) {
                                ProgressView().tint(.white).scaleEffect(0.75)
                                Text("Loading…").font(.hxCallout)
                            }
                        } else {
                            Label("Start", systemImage: "play.fill").font(.hxCallout)
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Color.hxCyan)
                .disabled(runnerCoordinator.isModelLoading)
            } else if phase == .running {
                Button {
                    lightFeedback.impactOccurred()
                    runnerCoordinator.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.hxCallout)
                }
                .buttonStyle(.glass)
            } else if phase == .paused {
                Button {
                    mediumFeedback.impactOccurred()
                    runnerCoordinator.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.hxCallout)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.hxSuccess)
            } else if phase == .finished {
                Button {
                    mediumFeedback.impactOccurred()
                    if let summary = runnerCoordinator.buildSummary() {
                        runResultsShown = true
                        appModel.openResults(summary: summary)
                    }
                } label: {
                    Label("Results", systemImage: "chart.bar.fill")
                        .font(.hxCallout)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.hxCyan)

                Button {
                    runResultsShown = false
                    runnerCoordinator.reset()
                } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .font(.hxCallout)
                }
                .buttonStyle(.glass)
            }

            // End Run (active states only — back button covers idle/finished)
            if phase == .running || phase == .paused {
                Button {
                    runnerCoordinator.finish()
                } label: {
                    Label("End Run", systemImage: "xmark.circle.fill")
                        .font(.hxCallout)
                }
                .buttonStyle(.glass)
                .tint(Color.hxDanger)
            }
        }
        .padding(.horizontal, HXSpacing.xl)
        .padding(.vertical, HXSpacing.md)
        .background(.ultraThinMaterial)
    }

    private func endTaskAndReturnToHub() {
        runnerCoordinator.finish()
        Task {
            await runnerCoordinator.switchInputSource(to: .liveCamera)
            appModel.refreshPreviewSource()
            dismiss()
        }
    }
}
