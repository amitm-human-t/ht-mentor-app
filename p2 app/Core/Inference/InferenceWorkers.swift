import Foundation

// MARK: - TaskInferenceWorker

/// Self-scheduling actor that continuously pulls the latest frame from the bus
/// and runs task-model inference. RunnerCoordinator reads `snapshot()` without
/// waiting — inference and the run loop are fully decoupled.
actor TaskInferenceWorker {
    private let task: TaskIdentifier
    private let frameBus: CameraFrameBus
    private let modelRegistry: CoreMLModelRegistry
    private(set) var latestSnapshot = TaskInferenceSnapshot(
        modelLoaded: false, outputNames: [], detections: [])
    private var workerTask: Task<Void, Never>?

    init(task: TaskIdentifier, frameBus: CameraFrameBus, modelRegistry: CoreMLModelRegistry) {
        self.task = task
        self.frameBus = frameBus
        self.modelRegistry = modelRegistry
    }

    deinit { workerTask?.cancel() }

    /// Start the self-scheduling inference loop. Safe to call multiple times —
    /// cancels the previous loop first.
    func start() {
        workerTask?.cancel()
        // Capture bus + registry strongly (they outlive the worker via AppModel),
        // capture self weakly to avoid a retain cycle with the stored Task.
        let capturedTask = task
        let capturedBus = frameBus
        let capturedRegistry = modelRegistry
        workerTask = Task { [weak self] in
            let stream = await capturedBus.subscribe()
            for await frame in stream {
                guard !Task.isCancelled else { break }
                let snap = await capturedRegistry.taskInference(
                    for: capturedTask,
                    pixelBuffer: frame.pixelBuffer,
                    exifOrientation: frame.exifOrientation
                )
                await self?.setSnapshot(snap)
            }
        }
    }

    func stop() {
        workerTask?.cancel()
        workerTask = nil
        latestSnapshot = TaskInferenceSnapshot(modelLoaded: false, outputNames: [], detections: [])
    }

    /// Non-blocking read — just returns the last completed inference result.
    func snapshot() -> TaskInferenceSnapshot { latestSnapshot }

    private func setSnapshot(_ snap: TaskInferenceSnapshot) {
        latestSnapshot = snap
    }
}

// MARK: - InstrumentInferenceWorker

actor InstrumentInferenceWorker {
    private let frameBus: CameraFrameBus
    private let modelRegistry: CoreMLModelRegistry
    private(set) var latestSnapshot = InstrumentInferenceSnapshot(
        modelLoaded: false, outputNames: [], tip: nil)
    private var workerTask: Task<Void, Never>?

    init(frameBus: CameraFrameBus, modelRegistry: CoreMLModelRegistry) {
        self.frameBus = frameBus
        self.modelRegistry = modelRegistry
    }

    deinit { workerTask?.cancel() }

    func start() {
        workerTask?.cancel()
        let capturedBus = frameBus
        let capturedRegistry = modelRegistry
        workerTask = Task { [weak self] in
            let stream = await capturedBus.subscribe()
            for await frame in stream {
                guard !Task.isCancelled else { break }
                let snap = await capturedRegistry.instrumentInference(
                    pixelBuffer: frame.pixelBuffer,
                    exifOrientation: frame.exifOrientation
                )
                await self?.setSnapshot(snap)
            }
        }
    }

    func stop() {
        workerTask?.cancel()
        workerTask = nil
        latestSnapshot = InstrumentInferenceSnapshot(modelLoaded: false, outputNames: [], tip: nil)
    }

    func snapshot() -> InstrumentInferenceSnapshot { latestSnapshot }

    private func setSnapshot(_ snap: InstrumentInferenceSnapshot) {
        latestSnapshot = snap
    }
}
