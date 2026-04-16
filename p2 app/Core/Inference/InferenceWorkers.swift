import Foundation

actor TaskInferenceWorker {
    private let task: TaskIdentifier
    private let frameBus: CameraFrameBus
    private let modelRegistry: CoreMLModelRegistry

    init(task: TaskIdentifier, frameBus: CameraFrameBus, modelRegistry: CoreMLModelRegistry) {
        self.task = task
        self.frameBus = frameBus
        self.modelRegistry = modelRegistry
    }

    func evaluateLatestFrame() async -> TaskInferenceSnapshot {
        guard let frame = await frameBus.latestFrame() else {
            return TaskInferenceSnapshot(modelLoaded: false, outputNames: [], detections: [])
        }
        return await modelRegistry.taskInference(for: task, pixelBuffer: frame.pixelBuffer)
    }
}

actor InstrumentInferenceWorker {
    private let frameBus: CameraFrameBus
    private let modelRegistry: CoreMLModelRegistry

    init(frameBus: CameraFrameBus, modelRegistry: CoreMLModelRegistry) {
        self.frameBus = frameBus
        self.modelRegistry = modelRegistry
    }

    func evaluateLatestFrame() async -> InstrumentInferenceSnapshot {
        guard let frame = await frameBus.latestFrame() else {
            return InstrumentInferenceSnapshot(modelLoaded: false, outputNames: [], tip: nil)
        }
        return await modelRegistry.instrumentInference(pixelBuffer: frame.pixelBuffer)
    }
}
