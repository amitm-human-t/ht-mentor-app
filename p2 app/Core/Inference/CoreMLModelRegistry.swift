import Foundation
import CoreML
import Vision
import AVFoundation
import OSLog

/// Loads bundled YOLO-style models, runs Vision requests, and normalizes the
/// raw `1 x N x 6` output rows into task detections.
actor CoreMLModelRegistry {
    private struct LoadedModel {
        let name: String
        let model: MLModel
        let visionModel: VNCoreMLModel
        let outputNames: [String]
        let classLabels: [Int: String]
    }

    private var taskModels: [TaskIdentifier: LoadedModel] = [:]
    private var instrumentModel: LoadedModel?

    func prepareForTask(_ task: TaskIdentifier) async throws {
        guard let taskAsset = modelAsset(for: task) else { return }
        let taskModel = try loadModel(named: task.rawValue, asset: taskAsset, fallbackLabels: fallbackLabels(for: task))
        let instrumentAsset = BundledAsset(pathComponents: ["models", "instrument"], fileExtension: "mlpackage", kind: .model)
        let instrumentModel = try loadModel(named: "instrument", asset: instrumentAsset, fallbackLabels: [0: "Tip", 1: "manual"])
        taskModels[task] = taskModel
        self.instrumentModel = instrumentModel
        let taskOutputs = taskModel.outputNames.joined(separator: ",")
        let instrumentOutputs = instrumentModel.outputNames.joined(separator: ",")
        AppLogger.inference.info("Prepared task model \(task.rawValue, privacy: .public) outputs: \(taskOutputs, privacy: .public)")
        AppLogger.inference.info("Prepared instrument model outputs: \(instrumentOutputs, privacy: .public)")
    }

    func taskInference(for task: TaskIdentifier, pixelBuffer: CVPixelBuffer) async -> TaskInferenceSnapshot {
        guard let model = taskModels[task] else {
            return TaskInferenceSnapshot(modelLoaded: false, outputNames: [], detections: [])
        }

        do {
            let observations = try await performVisionInference(with: model.visionModel, pixelBuffer: pixelBuffer)
            let detections = parseYOLODetections(observations: observations, classLabels: model.classLabels)
            if !detections.isEmpty {
                AppLogger.inference.debug("Task inference produced \(detections.count) detections for \(task.rawValue, privacy: .public)")
            }
            return TaskInferenceSnapshot(modelLoaded: true, outputNames: model.outputNames, detections: detections)
        } catch {
            AppLogger.inference.error("Task inference failed for \(task.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return TaskInferenceSnapshot(modelLoaded: true, outputNames: model.outputNames, detections: [])
        }
    }

    func instrumentInference(pixelBuffer: CVPixelBuffer) async -> InstrumentInferenceSnapshot {
        guard let instrumentModel else {
            return InstrumentInferenceSnapshot(modelLoaded: false, outputNames: [], tip: nil)
        }

        do {
            let observations = try await performVisionInference(with: instrumentModel.visionModel, pixelBuffer: pixelBuffer)
            let detections = parseYOLODetections(observations: observations, classLabels: instrumentModel.classLabels)
            let tipDetection = detections.max(by: { $0.confidence < $1.confidence })
            let tip = tipDetection.map {
                InstrumentTipPayload(
                    location: CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY),
                    confidence: $0.confidence
                )
            }
            return InstrumentInferenceSnapshot(modelLoaded: true, outputNames: instrumentModel.outputNames, tip: tip)
        } catch {
            AppLogger.inference.error("Instrument inference failed: \(error.localizedDescription, privacy: .public)")
            return InstrumentInferenceSnapshot(modelLoaded: true, outputNames: instrumentModel.outputNames, tip: nil)
        }
    }

    private func loadModel(
        named name: String,
        asset: BundledAsset,
        fallbackLabels: [Int: String]
    ) throws -> LoadedModel {
        guard let url = locateCompiledModel(for: asset) ?? asset.locate(in: .main) else {
            throw ModelRegistryError.modelMissing(name)
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let visionModel = try VNCoreMLModel(for: model)
        let outputNames = model.modelDescription.outputDescriptionsByName.keys.sorted()
        let classLabels = extractClassLabels(from: model) ?? fallbackLabels
        AppLogger.inference.info("Loaded model \(name, privacy: .public) from \(url.path, privacy: .public)")
        AppLogger.inference.debug("Model \(name, privacy: .public) labels: \(String(describing: classLabels), privacy: .public)")

        return LoadedModel(
            name: name,
            model: model,
            visionModel: visionModel,
            outputNames: outputNames,
            classLabels: classLabels
        )
    }

    private func locateCompiledModel(for asset: BundledAsset) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL, let modelName = asset.pathComponents.last else { return nil }
        let folderPath = asset.pathComponents.dropLast().joined(separator: "/")

        let direct = resourceURL.appendingPathComponent("\(modelName).mlmodelc")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        let foldered = resourceURL.appendingPathComponent(folderPath).appendingPathComponent("\(modelName).mlmodelc")
        if FileManager.default.fileExists(atPath: foldered.path) {
            return foldered
        }

        return nil
    }

    private func performVisionInference(
        with visionModel: VNCoreMLModel,
        pixelBuffer: CVPixelBuffer
    ) async throws -> [VNObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: request.results ?? [])
            }
            request.imageCropAndScaleOption = .scaleFill

            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseYOLODetections(
        observations: [VNObservation],
        classLabels: [Int: String]
    ) -> [TaskDetection] {
        let featureObservations = observations.compactMap { $0 as? VNCoreMLFeatureValueObservation }
        guard let multiArray = featureObservations.compactMap(\.featureValue.multiArrayValue).first else {
            return []
        }

        let dimensions = multiArray.shape.map(\.intValue)
        guard dimensions.count == 3, dimensions[0] == 1, dimensions[2] >= 6 else {
            AppLogger.inference.error("Unexpected YOLO output shape: \(String(describing: dimensions), privacy: .public)")
            return []
        }

        let rowCount = dimensions[1]
        var detections: [TaskDetection] = []

        var keptCount = 0
        for row in 0..<rowCount {
            // Ultralytics-exported models in this project emit one row per
            // detection in the form [x1, y1, x2, y2, confidence, classIndex].
            let x1 = CGFloat(truncating: multiArray[[0, row as NSNumber, 0]])
            let y1 = CGFloat(truncating: multiArray[[0, row as NSNumber, 1]])
            let x2 = CGFloat(truncating: multiArray[[0, row as NSNumber, 2]])
            let y2 = CGFloat(truncating: multiArray[[0, row as NSNumber, 3]])
            let confidence = Float(truncating: multiArray[[0, row as NSNumber, 4]])
            let classIndex = Int(truncating: multiArray[[0, row as NSNumber, 5]])

            guard confidence > 0.20 else { continue }

            let normalizedRect = normalizeRect(x1: x1, y1: y1, x2: x2, y2: y2)
            let label = classLabels[classIndex] ?? "class_\(classIndex)"
            detections.append(.init(id: UUID(), label: label, confidence: confidence, boundingBox: normalizedRect))
            keptCount += 1
        }

        if rowCount > 0 && keptCount == 0 {
            AppLogger.inference.debug("Model produced \(rowCount) candidate rows but none passed the confidence threshold")
        }

        return detections
    }

    private func normalizeRect(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) -> CGRect {
        let rawRect = CGRect(
            x: min(x1, x2),
            y: min(y1, y2),
            width: abs(x2 - x1),
            height: abs(y2 - y1)
        )

        let rect: CGRect
        if rawRect.maxX > 1 || rawRect.maxY > 1 {
            // Some exports yield model-space pixels rather than normalized
            // coordinates. The validation notes documented 512 as the expected
            // model input size for this app's YOLO benchmark pipeline.
            rect = CGRect(
                x: rawRect.origin.x / 512,
                y: rawRect.origin.y / 512,
                width: rawRect.size.width / 512,
                height: rawRect.size.height / 512
            )
        } else {
            rect = rawRect
        }

        return CGRect(
            x: max(0, min(1, rect.origin.x)),
            y: max(0, min(1, rect.origin.y)),
            width: max(0, min(1 - rect.origin.x, rect.size.width)),
            height: max(0, min(1 - rect.origin.y, rect.size.height))
        )
    }

    private func extractClassLabels(from model: MLModel) -> [Int: String]? {
        guard
            let creatorDefined = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String],
            let namesString = creatorDefined["names"]
        else {
            return nil
        }

        let pattern = "(\\d+)\\s*:\\s*'([^']+)'"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(namesString.startIndex..<namesString.endIndex, in: namesString)

        var labels: [Int: String] = [:]
        for match in regex.matches(in: namesString, range: range) {
            guard
                let indexRange = Range(match.range(at: 1), in: namesString),
                let labelRange = Range(match.range(at: 2), in: namesString),
                let index = Int(namesString[indexRange])
            else {
                continue
            }
            labels[index] = String(namesString[labelRange])
        }

        return labels.isEmpty ? nil : labels
    }

    private func modelAsset(for task: TaskIdentifier) -> BundledAsset? {
        switch task {
        case .keyLock:
            return BundledAsset(pathComponents: ["models", "keylock"], fileExtension: "mlpackage", kind: .model)
        case .tipPositioning:
            return BundledAsset(pathComponents: ["models", "tippos"], fileExtension: "mlpackage", kind: .model)
        case .rubberBand:
            return BundledAsset(pathComponents: ["models", "rubberband"], fileExtension: "mlpackage", kind: .model)
        case .springsSuturing:
            return BundledAsset(pathComponents: ["models", "springs"], fileExtension: "mlpackage", kind: .model)
        case .manualScoring:
            return nil
        }
    }

    private func fallbackLabels(for task: TaskIdentifier) -> [Int: String] {
        switch task {
        case .keyLock:
            return [0: "key", 1: "logo", 2: "slot", 3: "in", 4: "locked"]
        case .tipPositioning:
            return [0: "tip", 1: "logo", 2: "slot", 3: "hover", 4: "in"]
        case .rubberBand:
            return [0: "bands", 1: "pin", 2: "ring", 3: "logo"]
        case .springsSuturing:
            return [0: "logo", 1: "spring", 2: "blue", 3: "loop", 4: "loop_needle", 5: "loop_thread"]
        case .manualScoring:
            return [:]
        }
    }
}

enum ModelRegistryError: LocalizedError {
    case modelMissing(String)
    case invalidModel(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let model):
            return "Missing bundled model asset: \(model)"
        case .invalidModel(let model):
            return "Invalid CoreML package: \(model)"
        }
    }
}

struct TaskInferenceSnapshot: Sendable {
    let modelLoaded: Bool
    let outputNames: [String]
    let detections: [TaskDetection]
}

struct InstrumentInferenceSnapshot: Sendable {
    let modelLoaded: Bool
    let outputNames: [String]
    let tip: InstrumentTipPayload?
}
