import SwiftUI

struct TaskRunnerView: View {
    let appModel: AppModel
    private let runnerCoordinator: RunnerCoordinator
    private let debugVideoFrameSource: DebugVideoFrameSource
    let taskDefinition: TaskDefinition

    @State private var selectedMode: TaskMode = .guided
    @State private var isControlPanelVisible = true

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
            if runnerCoordinator.activeTask?.id != taskDefinition.id {
                let preferredMode = taskDefinition.supportedModes.contains(.guided)
                    ? TaskMode.guided
                    : taskDefinition.supportedModes.first ?? .manual
                selectedMode = preferredMode
                runnerCoordinator.prepare(task: taskDefinition, mode: preferredMode)
            }
        }
        .onDisappear {
            if let summary = runnerCoordinator.buildSummary(),
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

            // Quick run controls
            let phase = runnerCoordinator.stateMachine.phase

            if phase == .idle || phase == .error || phase == .finished {
                Button {
                    Task { await runnerCoordinator.start() }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.hxCallout)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.hxCyan)
            } else if phase == .running {
                Button {
                    runnerCoordinator.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.hxCallout)
                }
                .buttonStyle(.glass)
            } else if phase == .paused {
                Button {
                    runnerCoordinator.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.hxCallout)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.hxSuccess)
            }

            Button {
                runnerCoordinator.finish()
            } label: {
                Label("End Run", systemImage: "xmark.circle.fill")
                    .font(.hxCallout)
            }
            .buttonStyle(.glass)
            .tint(Color.hxDanger)
            .disabled(phase == .idle)
        }
        .padding(.horizontal, HXSpacing.xl)
        .padding(.vertical, HXSpacing.md)
        .background(.ultraThinMaterial)
    }
}
