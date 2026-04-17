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
            case .liveCamera:
                return "Live Camera"
            case .debugVideo:
                return "Debug Video"
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

    /// Non-nil during a BLE reconnect window in `.lockedSprint` mode.
    /// Counts down from 10 to 0; reaching 0 auto-finishes the run.
    private(set) var disconnectCountdown: Int? = nil

    private let cameraService: CameraService
    private let debugVideoFrameSource: DebugVideoFrameSource
    private let bleManager: any HandXBLEProvider
    private let modelRegistry: CoreMLModelRegistry
    private let permissionCenter: PermissionCenter
    private let frameBus: CameraFrameBus
    private let audioService: AudioService?
    private var taskEngine: any TaskEngine = PlaceholderTaskEngine()
    private(set) var taskStartDate: Date?
    private var trainerActions: [TrainerAction] = []
    private var runLoopTask: Task<Void, Never>?
    private var reconnectCountdownTask: Task<Void, Never>?
    private var taskInferenceWorker: TaskInferenceWorker?
    private var instrumentInferenceWorker: InstrumentInferenceWorker?

    init(
        cameraService: CameraService,
        debugVideoFrameSource: DebugVideoFrameSource,
        bleManager: any HandXBLEProvider,
        modelRegistry: CoreMLModelRegistry,
        permissionCenter: PermissionCenter,
        frameBus: CameraFrameBus,
        audioService: AudioService? = nil
    ) {
        self.cameraService = cameraService
        self.debugVideoFrameSource = debugVideoFrameSource
        self.bleManager = bleManager
        self.modelRegistry = modelRegistry
        self.permissionCenter = permissionCenter
        self.frameBus = frameBus
        self.audioService = audioService
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
        reconnectCountdownTask?.cancel()
        reconnectCountdownTask = nil
        disconnectCountdown = nil
        runLoopTask?.cancel()
        stopFrameSources()
        stateMachine.finish()
        AppLogger.runtime.info("Runner finished")
    }

    /// Switch the active frame source (camera ↔ debug video).
    /// Safe to call at any run phase — pauses the run if active, swaps source, then resumes.
    func switchInputSource(to newSource: InputSource) async {
        guard newSource != inputSource else { return }
        AppLogger.runtime.info("Switching input source: \(self.inputSource.rawValue, privacy: .public) → \(newSource.rawValue, privacy: .public)")

        let wasRunning = stateMachine.phase == .running
        if wasRunning {
            runLoopTask?.cancel()
        }

        // Stop both sources — workers stay subscribed to frameBus, just stop feeding it
        cameraService.stopSession()
        debugVideoFrameSource.stop()

        inputSource = newSource

        if wasRunning || stateMachine.phase == .paused {
            // Only restart frame source if we were actually running/paused (not idle/finished)
            do {
                try await startFrameSource()
                if wasRunning { beginRunLoop() }
            } catch {
                AppLogger.runtime.error("Frame source switch failed: \(error.localizedDescription, privacy: .public)")
                currentFailure = .startup(error.localizedDescription)
                stateMachine.fail()
            }
        }
    }

    // MARK: - BLE Disconnect Policy

    /// Called from tick() when a BLE drop is detected during a locked-sprint run.
    /// Pauses immediately and starts a 10-second reconnect window.
    private func handleBLEDisconnect() {
        guard stateMachine.phase == .running, selectedMode == .lockedSprint else { return }
        guard reconnectCountdownTask == nil else { return }  // already counting down

        AppLogger.runtime.warning("HandX disconnected during locked sprint — starting 10s reconnect window")
        pause()

        disconnectCountdown = 10
        reconnectCountdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: 9, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.disconnectCountdown = remaining
            }
            // Countdown expired — check one last time whether BLE reconnected
            guard !Task.isCancelled else { return }
            if self.bleManager.connectionState == .connected {
                self.clearReconnectState()
                self.resume()
                AppLogger.runtime.info("HandX reconnected — resuming run")
            } else {
                self.clearReconnectState()
                self.currentFailure = .bleDisconnectTimeout
                self.finish()
                AppLogger.runtime.error("HandX reconnect timed out — run ended")
            }
        }
    }

    /// Called when BLE reconnects during the countdown window.
    private func handleBLEReconnect() {
        guard reconnectCountdownTask != nil else { return }
        AppLogger.runtime.info("HandX reconnected within window — cancelling countdown")
        clearReconnectState()
        resume()
    }

    private func clearReconnectState() {
        reconnectCountdownTask?.cancel()
        reconnectCountdownTask = nil
        disconnectCountdown = nil
    }

    /// Convenience for HUD and panel views — avoids leaking `bleManager` reference.
    var bleConnected: Bool { bleManager.connectionState == .connected }

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

        // BLE disconnect detection for locked-sprint mode
        if selectedMode == .lockedSprint {
            if bleManager.connectionState != .connected && reconnectCountdownTask == nil {
                handleBLEDisconnect()
                return
            } else if bleManager.connectionState == .connected && reconnectCountdownTask != nil {
                handleBLEReconnect()
            }
        }

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
        let output = taskEngine.step(inputs: inputs)

        // Dispatch audio events emitted by the engine this tick
        for event in output.events where event.name == "audio_callout" {
            if let dir = event.payload["dir"], let file = event.payload["file"] {
                audioService?.playCallout(dir: dir, file: file)
            }
        }

        latestOutput = output
    }

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
        // Stop both unconditionally — safe to call stop on an already-stopped source
        cameraService.stopSession()
        debugVideoFrameSource.stop()
    }
}

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
