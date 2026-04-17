import SwiftUI

struct TaskRunnerView: View {
    let appModel: AppModel
    private let runnerCoordinator: RunnerCoordinator
    private let debugVideoFrameSource: DebugVideoFrameSource
    let taskDefinition: TaskDefinition
    @State private var selectedMode: TaskMode = .guided
    @State private var isControlPanelVisible = false

    init(appModel: AppModel, taskDefinition: TaskDefinition) {
        self.appModel = appModel
        self.taskDefinition = taskDefinition
        self.runnerCoordinator = appModel.runnerCoordinator
        self.debugVideoFrameSource = appModel.debugVideoFrameSource
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                AppPreviewStageView(appModel: appModel, showsControls: false, compact: false)
                    .ignoresSafeArea()

                runnerOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if isControlPanelVisible {
                    HStack {
                        Spacer(minLength: 0)
                        controlBar
                            .frame(width: max(320, min(400, proxy.size.width * 0.3)))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    .padding(20)
                }

                runnerChrome
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color(red: 0.07, green: 0.08, blue: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .navigationTitle(taskDefinition.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if runnerCoordinator.activeTask?.id != taskDefinition.id {
                let preferredMode = taskDefinition.supportedModes.contains(.guided) ? TaskMode.guided : taskDefinition.supportedModes.first ?? .manual
                selectedMode = preferredMode
                runnerCoordinator.prepare(task: taskDefinition, mode: preferredMode)
            }
        }
        .onDisappear {
            if let summary = runnerCoordinator.buildSummary(), runnerCoordinator.stateMachine.phase == .finished {
                appModel.persistCompletedRun(summary: summary)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isControlPanelVisible)
        .overlay {
            if let countdown = runnerCoordinator.disconnectCountdown {
                BLEReconnectOverlay(countdown: countdown) {
                    runnerCoordinator.finish()
                }
                .animation(.hxModal, value: countdown)
            }
        }
    }

    private var runnerOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(runnerCoordinator.latestOutput.statusText)
                .font(.headline)
                .foregroundStyle(.white)
            Text("Target: \(runnerCoordinator.latestOutput.targetInfo)")
            Text("Score: \(runnerCoordinator.latestOutput.score)")
            Text("Progress: \(runnerCoordinator.latestOutput.progress.completed)/\(runnerCoordinator.latestOutput.progress.total)")
            Text("Input: \(runnerCoordinator.inputSource.title)")
            if runnerCoordinator.inputSource == .debugVideo {
                Text("Video: \(debugVideoFrameSource.selectedVideoURL?.lastPathComponent ?? "Not selected")")
            }
            Text("Detections: \(runnerCoordinator.latestInferenceStatus.taskDetectionCount)")
            if !runnerCoordinator.latestInferenceStatus.taskOutputNames.isEmpty {
                Text("Outputs: \(runnerCoordinator.latestInferenceStatus.taskOutputNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let failure = runnerCoordinator.currentFailure {
                Text(failure.localizedDescription)
                    .foregroundStyle(.orange)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding()
    }

    private var runnerChrome: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    isControlPanelVisible.toggle()
                } label: {
                    Label(isControlPanelVisible ? "Hide Controls" : "Show Controls", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button {
                    runnerCoordinator.finish()
                } label: {
                    Label("End Run", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Spacer()
        }
    }

    private var controlBar: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Runner Controls")
                        .font(.title3.bold())
                    Spacer()
                    Button("Close") {
                        isControlPanelVisible = false
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Preview Source")
                    .font(.headline)

                Picker("Source", selection: inputSourceBinding) {
                    ForEach(RunnerCoordinator.InputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                if runnerCoordinator.inputSource == .debugVideo {
                    Picker("Embedded Video", selection: embeddedVideoSelection) {
                        ForEach(appModel.embeddedVideosForCurrentTask) { video in
                            Text(video.name).tag(Optional(video.url))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Picker("Mode", selection: $selectedMode) {
                ForEach(taskDefinition.supportedModes, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedMode) { _, newValue in
                runnerCoordinator.prepare(task: taskDefinition, mode: newValue)
            }

            HStack {
                Button("Start") {
                    Task {
                        await runnerCoordinator.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Pause") {
                    runnerCoordinator.pause()
                }
                .buttonStyle(.bordered)

                Button("Resume") {
                    runnerCoordinator.resume()
                }
                .buttonStyle(.bordered)

                Button("Reset") {
                    runnerCoordinator.reset()
                }
                .buttonStyle(.bordered)

                Button("Finish") {
                    runnerCoordinator.finish()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Button("Skip Target") {
                    runnerCoordinator.registerTrainerAction(.skipTarget)
                }
                Button("Mark Success") {
                    runnerCoordinator.registerTrainerAction(.markSuccess)
                }
                Button("Mark Failure") {
                    runnerCoordinator.registerTrainerAction(.markFailure)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var inputSourceBinding: Binding<RunnerCoordinator.InputSource> {
        Binding(
            get: { runnerCoordinator.inputSource },
            set: { runnerCoordinator.inputSource = $0 }
        )
    }

    private var embeddedVideoSelection: Binding<URL?> {
        Binding(
            get: { debugVideoFrameSource.selectedVideoURL },
            set: { newValue in
                guard let newValue else { return }
                debugVideoFrameSource.selectVideo(url: newValue)
            }
        )
    }
}
