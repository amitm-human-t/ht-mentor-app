import Foundation
import Combine
import OSLog

@MainActor
final class RunnerCoordinator: ObservableObject {
    enum InputSource: String, CaseIterable, Identifiable {
        case liveCamera
        case debugVideo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveCamera:
                return "Live Camera"
            case .debugVideo:
                return "Debug Video"
            }
        }
    }

    @Published private(set) var stateMachine = RunStateMachine()
    @Published private(set) var latestOutput = TaskStepOutput(
        statusText: "Idle",
        score: 0,
        targetInfo: "No task selected",
        progress: ProgressSnapshot(completed: 0, total: 0),
        events: [],
        overlayPayload: .empty
    )
    @Published private(set) var activeTask: TaskDefinition?
    @Published private(set) var selectedMode: TaskMode = .guided
    @Published private(set) var currentFailure: RunnerFailure?
    @Published var inputSource: InputSource = .liveCamera
    @Published private(set) var latestInferenceStatus = InferenceStatus(
        taskModelLoaded: false,
        instrumentModelLoaded: false,
        taskOutputNames: [],
        taskDetectionCount: 0,
        instrumentTipDetected: false
    )

    private let cameraService: CameraService
    private let debugVideoFrameSource: DebugVideoFrameSource
    private let bleManager: HandXBLEManager
    private let modelRegistry: CoreMLModelRegistry
    private let permissionCenter: PermissionCenter
    private let frameBus: CameraFrameBus
    private var taskEngine: any TaskEngine = PlaceholderTaskEngine()
    private var taskStartDate: Date?
    private var trainerActions: [TrainerAction] = []
    private var runLoopTask: Task<Void, Never>?
    private var taskInferenceWorker: TaskInferenceWorker?
    private var instrumentInferenceWorker: InstrumentInferenceWorker?

    init(
        cameraService: CameraService,
        debugVideoFrameSource: DebugVideoFrameSource,
        bleManager: HandXBLEManager,
        modelRegistry: CoreMLModelRegistry,
        permissionCenter: PermissionCenter,
        frameBus: CameraFrameBus
    ) {
        self.cameraService = cameraService
        self.debugVideoFrameSource = debugVideoFrameSource
        self.bleManager = bleManager
        self.modelRegistry = modelRegistry
        self.permissionCenter = permissionCenter
        self.frameBus = frameBus
    }

    func prepare(task: TaskDefinition, mode: TaskMode) {
        activeTask = task
        selectedMode = mode
        taskEngine = engine(for: task.id)
        taskEngine.reset()
        taskEngine.configure(TaskConfig(task: task.id, mode: mode, targetCount: 10))
        latestOutput = TaskStepOutput(
            statusText: "Prepared",
            score: 0,
            targetInfo: task.subtitle,
            progress: ProgressSnapshot(completed: 0, total: 10),
            events: [],
            overlayPayload: .empty
        )
        currentFailure = nil
        latestInferenceStatus = InferenceStatus(
            taskModelLoaded: false,
            instrumentModelLoaded: false,
            taskOutputNames: [],
            taskDetectionCount: 0,
            instrumentTipDetected: false
        )
        trainerActions = []
        stateMachine = RunStateMachine()
    }

    func start() async {
        guard let activeTask else { return }
        currentFailure = nil
        AppLogger.runtime.info("Starting task \(activeTask.id.rawValue, privacy: .public) mode \(self.selectedMode.rawValue, privacy: .public) source \(self.inputSource.rawValue, privacy: .public)")
        if inputSource == .liveCamera {
            let permissions = await permissionCenter.refresh()
            guard permissions.camera == .authorized else {
                currentFailure = .cameraPermissionDenied
                AppLogger.runtime.error("Runner blocked by camera permission")
                stateMachine.fail()
                return
            }
        }
        if selectedMode == .lockedSprint && bleManager.connectionState != .connected {
            currentFailure = .bleRequired
            AppLogger.runtime.error("Runner blocked because BLE is required for locked sprint")
            stateMachine.fail()
            return
        }
        do {
            try await modelRegistry.prepareForTask(activeTask.id)
            try await startFrameSource()
            taskInferenceWorker = TaskInferenceWorker(task: activeTask.id, frameBus: frameBus, modelRegistry: modelRegistry)
            instrumentInferenceWorker = InstrumentInferenceWorker(frameBus: frameBus, modelRegistry: modelRegistry)
            taskEngine.start()
            taskStartDate = Date()
            stateMachine.start()
            beginRunLoop()
        } catch {
            AppLogger.runtime.error("Runner startup failed: \(error.localizedDescription, privacy: .public)")
            currentFailure = .startup(error.localizedDescription)
            stateMachine.fail()
        }
    }

    func pause() {
        guard stateMachine.phase == .running else { return }
        taskEngine.pause()
        stateMachine.pause()
        runLoopTask?.cancel()
    }

    func resume() {
        guard stateMachine.phase == .paused else { return }
        stateMachine.resume()
        beginRunLoop()
    }

    func reset() {
        runLoopTask?.cancel()
        stopFrameSources()
        taskEngine.reset()
        AppLogger.runtime.info("Runner reset")
        latestOutput = TaskStepOutput(
            statusText: "Reset",
            score: 0,
            targetInfo: activeTask?.subtitle ?? "No task selected",
            progress: ProgressSnapshot(completed: 0, total: 10),
            events: [],
            overlayPayload: .empty
        )
        currentFailure = nil
        latestInferenceStatus = InferenceStatus(
            taskModelLoaded: false,
            instrumentModelLoaded: false,
            taskOutputNames: [],
            taskDetectionCount: 0,
            instrumentTipDetected: false
        )
        stateMachine.reset()
    }

    func finish() {
        runLoopTask?.cancel()
        stopFrameSources()
        stateMachine.finish()
        AppLogger.runtime.info("Runner finished")
    }

    func registerTrainerAction(_ kind: TrainerAction.Kind) {
        trainerActions.append(.init(kind: kind, timestamp: Date().timeIntervalSinceReferenceDate))
    }

    func buildSummary() -> RunSummaryDraft? {
        guard let activeTask, let taskStartDate else { return nil }
        return SessionSummaryBuilder.makeSummary(
            task: activeTask,
            mode: selectedMode,
            startedAt: taskStartDate,
            endedAt: Date(),
            output: latestOutput,
            handXConnected: bleManager.connectionState == .connected
        )
    }

    private func beginRunLoop() {
        runLoopTask?.cancel()
        runLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func tick() async {
        guard stateMachine.phase == .running else { return }
        let elapsed = Date().timeIntervalSince(taskStartDate ?? Date())
        let taskInference = await taskInferenceWorker?.evaluateLatestFrame() ?? TaskInferenceSnapshot(modelLoaded: false, outputNames: [], detections: [])
        let instrumentInference = await instrumentInferenceWorker?.evaluateLatestFrame() ?? InstrumentInferenceSnapshot(modelLoaded: false, outputNames: [], tip: nil)
        let inputs = TaskInputs(
            elapsed: elapsed,
            handXSample: bleManager.latestSample,
            instrumentTip: instrumentInference.tip,
            taskDetections: taskInference.detections,
            trainerActions: trainerActions,
            inferenceInfo: InferenceStatus(
                taskModelLoaded: taskInference.modelLoaded,
                instrumentModelLoaded: instrumentInference.modelLoaded,
                taskOutputNames: taskInference.outputNames,
                taskDetectionCount: taskInference.detections.count,
                instrumentTipDetected: instrumentInference.tip != nil
            )
        )
        latestInferenceStatus = inputs.inferenceInfo
        latestOutput = taskEngine.step(inputs: inputs)
    }

    private func engine(for task: TaskIdentifier) -> any TaskEngine {
        switch task {
        case .keyLock:
            return KeyLockTaskEngine()
        case .tipPositioning, .rubberBand, .springsSuturing, .manualScoring:
            return PlaceholderTaskEngine()
        }
    }

    private func startFrameSource() async throws {
        switch inputSource {
        case .liveCamera:
            try await cameraService.startSession(frameBus: frameBus)
        case .debugVideo:
            try await debugVideoFrameSource.start(frameBus: frameBus)
        }
    }

    private func stopFrameSources() {
        switch inputSource {
        case .liveCamera:
            debugVideoFrameSource.stop()
        case .debugVideo:
            debugVideoFrameSource.stop()
            cameraService.stopSession()
        }
    }
}

enum RunnerFailure: LocalizedError, Equatable {
    case cameraPermissionDenied
    case bleRequired
    case startup(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera permission is required before the Task Runner can start."
        case .bleRequired:
            return "Locked Sprint requires an active HandX connection."
        case .startup(let message):
            return "Runner startup failed: \(message)"
        }
    }
}
