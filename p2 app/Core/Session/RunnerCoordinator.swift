import Foundation
import OSLog

@Observable
@MainActor
final class RunnerCoordinator {
    enum InputSource: String, CaseIterable, Identifiable {
        case liveCamera
        case debugVideo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveCamera:  return "Live Camera"
            case .debugVideo:  return "Debug Video"
            }
        }
    }

    private(set) var stateMachine = RunStateMachine()
    private(set) var latestOutput = TaskStepOutput(
        statusText: "Idle",
        score: 0,
        targetInfo: "No task selected",
        progress: ProgressSnapshot(completed: 0, total: 0),
        events: [],
        overlayPayload: .empty
    )
    private(set) var activeTask: TaskDefinition?
    private(set) var selectedMode: TaskMode = .guided
    private(set) var currentFailure: RunnerFailure?
    var inputSource: InputSource = .liveCamera
    private(set) var latestInferenceStatus = InferenceStatus(
        taskModelLoaded: false,
        instrumentModelLoaded: false,
        taskOutputNames: [],
        taskDetectionCount: 0,
        instrumentTipDetected: false
    )

    /// True while models are loading in the background after prepare().
    /// The Start button should be disabled / show a spinner while this is true.
    private(set) var isModelLoading = false

    /// Non-nil during a BLE reconnect window in `.lockedSprint` mode.
    private(set) var disconnectCountdown: Int? = nil

    // MARK: - Debug (only compiled in DEBUG builds)

    #if DEBUG
    private(set) var debugBoundingBoxesVisible = false
    /// Raw task-model detections from the last inference tick. Only populated
    /// while debugBoundingBoxesVisible is true.
    private(set) var debugAllDetections: [TaskDetection] = []
    private(set) var debugInstrumentTip: InstrumentTipPayload? = nil

    func toggleDebugBoundingBoxes() {
        debugBoundingBoxesVisible.toggle()
        if !debugBoundingBoxesVisible {
            debugAllDetections = []
            debugInstrumentTip = nil
        }
    }
    #endif

    // MARK: - Stored services

    private let cameraService: CameraService
    private let debugVideoFrameSource: DebugVideoFrameSource
    private let bleManager: any HandXBLEProvider
    private let modelRegistry: CoreMLModelRegistry
    private let permissionCenter: PermissionCenter
    private let frameBus: CameraFrameBus
    private let audioService: AudioService?
    private let thermalMonitor: ThermalMonitor
    private var taskEngine: any TaskEngine = PlaceholderTaskEngine()
    private(set) var taskStartDate: Date?
    private var trainerActions: [TrainerAction] = []
    /// Throttle counter for thermal-serious state (skip every other tick).
    private var thermalThrottleSkip = false

    @ObservationIgnored private var runLoopTask: Task<Void, Never>?
    @ObservationIgnored private var previewLoopTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectCountdownTask: Task<Void, Never>?
    @ObservationIgnored private var taskInferenceWorker: TaskInferenceWorker?
    @ObservationIgnored private var instrumentInferenceWorker: InstrumentInferenceWorker?

    /// Background model-preload task kicked off in prepare().
    /// Task<Void, Never> — errors are captured in modelLoadError.
    @ObservationIgnored private var modelPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var modelLoadError: Error?

    init(
        cameraService: CameraService,
        debugVideoFrameSource: DebugVideoFrameSource,
        bleManager: any HandXBLEProvider,
        modelRegistry: CoreMLModelRegistry,
        permissionCenter: PermissionCenter,
        frameBus: CameraFrameBus,
        audioService: AudioService? = nil,
        thermalMonitor: ThermalMonitor
    ) {
        self.cameraService = cameraService
        self.debugVideoFrameSource = debugVideoFrameSource
        self.bleManager = bleManager
        self.modelRegistry = modelRegistry
        self.permissionCenter = permissionCenter
        self.frameBus = frameBus
        self.audioService = audioService
        self.thermalMonitor = thermalMonitor
    }

    // MARK: - Lifecycle

    func prepare(task: TaskDefinition, mode: TaskMode) {
        previewLoopTask?.cancel()
        previewLoopTask = nil
        // Stop any workers from a previous task so beginPreviewInference() creates
        // fresh workers bound to the new task model.
        stopWorkers()
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
        #if DEBUG
        debugAllDetections = []
        debugInstrumentTip = nil
        #endif

        // Pre-warm models in the background so Start responds instantly.
        // The actor short-circuits if models are already loaded.
        modelPreloadTask?.cancel()
        modelLoadError = nil
        isModelLoading = true
        let registry = modelRegistry
        let taskID = task.id
        modelPreloadTask = Task {
            do {
                try await registry.prepareForTask(taskID)
            } catch {
                modelLoadError = error
                AppLogger.inference.fileError(
                    "Model preload failed for \(taskID.rawValue): \(error.localizedDescription)",
                    category: "inference"
                )
            }
            isModelLoading = false
        }
    }

    /// Start inference workers and (in DEBUG) a preview overlay loop while the
    /// task is in the idle phase. Workers started here are reused by start() so
    /// the first frame of the run has no cold-start delay.
    func beginPreviewInference() async {
        await modelPreloadTask?.value
        guard modelLoadError == nil, let activeTask else { return }

        // Reconnect frame source to the bus (camera may have been disconnected by a previous
        // finish(); debug video source may need to be started).
        do { try await startFrameSource() } catch { return }

        // Create workers if they haven't been created yet for this prepare cycle.
        if taskInferenceWorker == nil {
            let taskWorker = TaskInferenceWorker(
                task: activeTask.id, frameBus: frameBus, modelRegistry: modelRegistry)
            await taskWorker.start()
            let instrWorker = InstrumentInferenceWorker(
                frameBus: frameBus, modelRegistry: modelRegistry)
            await instrWorker.start()
            taskInferenceWorker = taskWorker
            instrumentInferenceWorker = instrWorker
        }

        #if DEBUG
        previewLoopTask?.cancel()
        previewLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.stateMachine.phase == .idle {
                if self.debugBoundingBoxesVisible {
                    let taskInference = await self.taskInferenceWorker?.snapshot()
                        ?? TaskInferenceSnapshot(modelLoaded: false, outputNames: [], detections: [])
                    let instrInference = await self.instrumentInferenceWorker?.snapshot()
                        ?? InstrumentInferenceSnapshot(modelLoaded: false, outputNames: [], tip: nil)
                    self.debugAllDetections = taskInference.detections
                    self.debugInstrumentTip = instrInference.tip
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        #endif
    }

    func start() async {
        guard let activeTask else { return }
        currentFailure = nil

        // Stop the idle-phase preview loop — workers will be reused for the run.
        previewLoopTask?.cancel()
        previewLoopTask = nil

        AppLogger.runtime.fileInfo(
            "Starting \(activeTask.id.rawValue) mode \(selectedMode.rawValue) source \(inputSource.rawValue)",
            category: "runtime"
        )

        if inputSource == .liveCamera {
            let permissions = await permissionCenter.refresh()
            guard permissions.camera == .authorized else {
                currentFailure = .cameraPermissionDenied
                AppLogger.runtime.fileError("Runner blocked by camera permission", category: "runtime")
                stateMachine.fail()
                return
            }
        }
        if selectedMode == .lockedSprint && bleManager.connectionState != .connected {
            currentFailure = .bleRequired
            AppLogger.runtime.fileError("Runner blocked — BLE required for locked sprint", category: "runtime")
            stateMachine.fail()
            return
        }

        // Await the background preload (instant if already done; short if still loading).
        await modelPreloadTask?.value

        if let loadError = modelLoadError {
            AppLogger.runtime.fileError("Runner start aborted — model load error: \(loadError.localizedDescription)", category: "runtime")
            currentFailure = .startup(loadError.localizedDescription)
            stateMachine.fail()
            return
        }

        do {
            try await startFrameSource()

            // Reuse workers started by beginPreviewInference() if available;
            // otherwise create them fresh.
            if taskInferenceWorker == nil || instrumentInferenceWorker == nil {
                let taskWorker = TaskInferenceWorker(
                    task: activeTask.id, frameBus: frameBus, modelRegistry: modelRegistry)
                await taskWorker.start()
                let instrWorker = InstrumentInferenceWorker(
                    frameBus: frameBus, modelRegistry: modelRegistry)
                await instrWorker.start()
                taskInferenceWorker = taskWorker
                instrumentInferenceWorker = instrWorker
            }

            taskEngine.start()
            taskStartDate = Date()
            stateMachine.start()
            audioService?.startBackground()
            beginRunLoop()
        } catch {
            AppLogger.runtime.fileError("Runner startup failed: \(error.localizedDescription)", category: "runtime")
            currentFailure = .startup(error.localizedDescription)
            stateMachine.fail()
        }
    }

    func pause() {
        guard stateMachine.phase == .running else { return }
        taskEngine.pause()
        stateMachine.pause()
        runLoopTask?.cancel()
        audioService?.pauseBackground()
    }

    func resume() {
        guard stateMachine.phase == .paused else { return }
        stateMachine.resume()
        audioService?.resumeBackground()
        beginRunLoop()
    }

    func reset() {
        runLoopTask?.cancel()
        previewLoopTask?.cancel()
        previewLoopTask = nil
        stopFrameSources()
        stopWorkers()
        taskEngine.reset()
        AppLogger.runtime.fileInfo("Runner reset", category: "runtime")
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
        #if DEBUG
        debugAllDetections = []
        debugInstrumentTip = nil
        #endif
        stateMachine.reset()
    }

    func finish() {
        reconnectCountdownTask?.cancel()
        reconnectCountdownTask = nil
        disconnectCountdown = nil
        runLoopTask?.cancel()
        previewLoopTask?.cancel()
        previewLoopTask = nil
        stopFrameSources()
        stopWorkers()
        audioService?.stopBackground()
        // Release the task model from memory — it will be reloaded next time this task runs.
        if let taskID = activeTask?.id {
            let registry = modelRegistry
            Task(priority: .background) { await registry.releaseTaskModel(for: taskID) }
        }
        stateMachine.finish()
        AppLogger.runtime.fileInfo("Runner finished", category: "runtime")
        #if DEBUG
        debugAllDetections = []
        debugInstrumentTip = nil
        #endif
    }

    // MARK: - Input source switching

    func switchInputSource(to newSource: InputSource) async {
        guard newSource != inputSource else { return }
        AppLogger.runtime.fileInfo(
            "Switching input source: \(inputSource.rawValue) → \(newSource.rawValue)",
            category: "runtime"
        )

        let wasRunning = stateMachine.phase == .running
        if wasRunning { runLoopTask?.cancel() }

        cameraService.stopPublishing()
        debugVideoFrameSource.stop()

        inputSource = newSource

        if wasRunning || stateMachine.phase == .paused {
            do {
                try await startFrameSource()
                if wasRunning { beginRunLoop() }
            } catch {
                AppLogger.runtime.fileError("Frame source switch failed: \(error.localizedDescription)", category: "runtime")
                currentFailure = .startup(error.localizedDescription)
                stateMachine.fail()
            }
        }
    }

    // MARK: - BLE Disconnect Policy

    private func handleBLEDisconnect() {
        guard stateMachine.phase == .running, selectedMode == .lockedSprint else { return }
        guard reconnectCountdownTask == nil else { return }

        AppLogger.runtime.fileWarning("HandX disconnected during locked sprint — starting 10s reconnect window", category: "runtime")
        pause()

        disconnectCountdown = 10
        reconnectCountdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: 9, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.disconnectCountdown = remaining
            }
            guard !Task.isCancelled else { return }
            if self.bleManager.connectionState == .connected {
                self.clearReconnectState()
                self.resume()
                AppLogger.runtime.fileInfo("HandX reconnected — resuming run", category: "runtime")
            } else {
                self.clearReconnectState()
                self.currentFailure = .bleDisconnectTimeout
                self.finish()
                AppLogger.runtime.fileError("HandX reconnect timed out — run ended", category: "runtime")
            }
        }
    }

    private func handleBLEReconnect() {
        guard reconnectCountdownTask != nil else { return }
        AppLogger.runtime.fileInfo("HandX reconnected within window — cancelling countdown", category: "runtime")
        clearReconnectState()
        resume()
    }

    private func clearReconnectState() {
        reconnectCountdownTask?.cancel()
        reconnectCountdownTask = nil
        disconnectCountdown = nil
    }

    var bleConnected: Bool { bleManager.connectionState == .connected }

    // MARK: - Trainer

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
            handXConnected: bleManager.connectionState == .connected,
            thermalStateName: thermalMonitor.displayName
        )
    }

    // MARK: - Run Loop

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

        // Thermal protection: skip inference entirely when critical; halve rate when serious.
        if thermalMonitor.shouldPauseInference { return }
        if thermalMonitor.shouldThrottle {
            thermalThrottleSkip.toggle()
            if thermalThrottleSkip { return }
        }

        if selectedMode == .lockedSprint {
            if bleManager.connectionState != .connected && reconnectCountdownTask == nil {
                handleBLEDisconnect()
                return
            } else if bleManager.connectionState == .connected && reconnectCountdownTask != nil {
                handleBLEReconnect()
            }
        }

        let elapsed = Date().timeIntervalSince(taskStartDate ?? Date())

        // Non-blocking snapshot reads — workers update independently at camera fps.
        // No await on inference: just grab whatever the worker last computed.
        let taskInference = await taskInferenceWorker?.snapshot()
            ?? TaskInferenceSnapshot(modelLoaded: false, outputNames: [], detections: [])
        let instrumentInference = await instrumentInferenceWorker?.snapshot()
            ?? InstrumentInferenceSnapshot(modelLoaded: false, outputNames: [], tip: nil)

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
        let output = taskEngine.step(inputs: inputs)

        for event in output.events where event.name == "audio_callout" {
            if let dir = event.payload["dir"], let file = event.payload["file"] {
                audioService?.playCallout(dir: dir, file: file)
            }
        }

        latestOutput = output

        #if DEBUG
        if debugBoundingBoxesVisible {
            debugAllDetections = taskInference.detections
            debugInstrumentTip = instrumentInference.tip
        }
        #endif
    }

    // MARK: - Private helpers

    private func engine(for task: TaskIdentifier) -> any TaskEngine {
        switch task {
        case .keyLock:          return KeyLockTaskEngine()
        case .tipPositioning:   return TipPositioningTaskEngine()
        case .rubberBand:       return RubberBandTaskEngine()
        case .springsSuturing:  return SpringsSuturingTaskEngine()
        case .manualScoring:    return ManualScoringEngine()
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
        // Disconnect camera from the frame bus but keep the session running so the
        // preview layer in Hub/TaskPicker stays live with no restart delay.
        cameraService.stopPublishing()
        debugVideoFrameSource.stop()
    }

    private func stopWorkers() {
        let tw = taskInferenceWorker
        let iw = instrumentInferenceWorker
        Task {
            await tw?.stop()
            await iw?.stop()
        }
        taskInferenceWorker = nil
        instrumentInferenceWorker = nil
    }
}

// MARK: - RunnerFailure

enum RunnerFailure: LocalizedError, Equatable {
    case cameraPermissionDenied
    case bleRequired
    case bleDisconnectTimeout
    case startup(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera permission is required before the Task Runner can start."
        case .bleRequired:
            return "Locked Sprint requires an active HandX connection."
        case .bleDisconnectTimeout:
            return "HandX disconnected and did not reconnect within 10 seconds."
        case .startup(let message):
            return "Runner startup failed: \(message)"
        }
    }
}
