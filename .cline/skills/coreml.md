# CoreML — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:coreml`
**Use when:** Model loading, inference, YOLO detection, model registry.

---

## Model Registry (Core/Inference/CoreMLModelRegistry.swift)

```swift
actor CoreMLModelRegistry {
    var confidenceThreshold: Float = 0.20
    var maxDetections: Int = 20

    // Load models for a task (async, called before start())
    func prepareForTask(_ taskID: TaskIdentifier) async throws

    // Get compiled model for inference
    func taskModel(for taskID: TaskIdentifier) -> VNCoreMLModel?
    func instrumentModel() -> VNCoreMLModel?
}
```

## Models Bundled

| Model | File | Classes |
|-------|------|---------|
| Key Lock | `keylock.mlpackage` | key(0), slot(1), logo(2) |
| Tip Positioning | `tippos.mlpackage` | tip(0), logo(1), slot(2), hover(3), in(4) |
| Rubber Band | `rubberband.mlpackage` | bands(0), pin(1), ring(2), logo(3) |
| Springs Suturing | `springs.mlpackage` | logo(0), spring(1), blue(2), loop(3), loop_needle(4), loop_thread(5) |
| Instrument | `instrument.mlpackage` | tip — instrument tip detector |

Models live at `p2 app/models/` (symlinked, NOT in git — see `.gitignore`).

## Inference Workers

```swift
// YOLO inference on task frames
actor TaskInferenceWorker {
    init(task: TaskIdentifier, frameBus: CameraFrameBus, modelRegistry: CoreMLModelRegistry)
    var latestSnapshot: TaskInferenceSnapshot { get }
}

// Instrument tip detection
actor InstrumentInferenceWorker {
    init(frameBus: CameraFrameBus, modelRegistry: CoreMLModelRegistry)
    var latestSnapshot: InstrumentInferenceSnapshot { get }
}
```

## Detection Output

```swift
struct TaskInferenceSnapshot: Sendable {
    var modelLoaded: Bool
    var outputNames: [String]
    var detections: [TaskDetection]   // normalized CGRect + classIndex + confidence
}

struct TaskDetection: Sendable {
    var classIndex: Int
    var confidence: Float
    var bbox: CGRect                  // normalized 0.0–1.0 (YOLO output coords)
}
```

## Coordinate Conversion (IMPORTANT)

YOLO outputs normalized coordinates that must go through AVCaptureVideoPreviewLayer:

```swift
// In CameraPreviewView / PreviewCoordinate (Core/Camera/)
// DO NOT use naive multiplication by view size
// USE layerRectConverted(fromMetadataOutputRect:)

func convertYOLORect(_ normalized: CGRect) -> CGRect {
    previewLayer.layerRectConverted(fromMetadataOutputRect: normalized)
}
```

Reference: `/Users/amitm/tk_models/ipad app/mentor tests/mentor model tests/CameraViewController.swift:726–733`

## Per-Class Detection Colors

```swift
// From TaskContracts.swift / DetectionColorPalette.swift
// tip=cyan, slot=orange, hover=yellow, in=green
// key=white, logo=teal, ring=pink, bands=yellow, pin=orange
// spring=orange, loop=yellow, loop_needle=green, loop_thread=teal
```

## Confidence Thresholds

- Default: `0.20` (set in `CoreMLModelRegistry.confidenceThreshold`)
- SpringsSuturing spring class: `0.35` (higher to reduce drift noise)
- Configurable from TrainerControlsPanel debug section
