# YOLO + LiDAR iPad Validation App Notes

This document captures the implementation decisions and practical lessons from this Xcode app so the same knowledge can be reused in a different app.

## Scope

This app ended up proving these pieces:

- loading Ultralytics-exported Core ML `.mlpackage` models at runtime
- running YOLO-style inference on live camera frames
- parsing raw Core ML output shaped like `1 x 300 x 6`
- drawing boxes on top of camera preview
- measuring inference latency and FPS
- using the LiDAR back camera as a single stable source for:
  - synchronized video frames for YOLO
  - synchronized depth frames for distance estimation

It also proved a few things that were unstable or not worth carrying forward:

- running separate RGB and LiDAR back-camera graphs in parallel was not reliable
- adding front camera PiP on top of the stable LiDAR + synchronized video/depth pipeline caused capture instability on this device/app setup

## Recommended Architecture

For a production app that needs both object detection and depth:

1. Use `AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)`.
2. Add one `AVCaptureVideoDataOutput`.
3. Add one `AVCaptureDepthDataOutput`.
4. Synchronize them with `AVCaptureDataOutputSynchronizer`.
5. Run YOLO on the synchronized video sample buffer.
6. Use the synchronized depth frame for distance lookup.

This was the most stable architecture found here.

Do not assume that:

- separate rear RGB camera + separate LiDAR session + front camera PiP
- or multiple competing rear-camera graphs

will work reliably on iPad just because the APIs allow similar combinations in theory.

## Model Packaging And Loading

### Expected model format

Ultralytics-exported Core ML models were added as `.mlpackage` resources.
At build time they appear in the app bundle as compiled `.mlmodelc`.

Runtime loading pattern:

```swift
let configuration = MLModelConfiguration()
configuration.computeUnits = .all

let model = try MLModel(contentsOf: url, configuration: configuration)
let visionModel = try VNCoreMLModel(for: model)
let request = VNCoreMLRequest(model: visionModel, completionHandler: ...)
request.imageCropAndScaleOption = .scaleFill
```

### Discovering bundled models

This app discovered compiled models by scanning:

- `Bundle.main.resourceURL`
- `Bundle.main.resourceURL?.appendingPathComponent("models")`

and filtering for `.mlmodelc`.

That is useful if you want model hot-swapping by file name rather than generated model classes.

### Compute units

Use `MLModelConfiguration.computeUnits` explicitly.

Useful options to expose in another app:

- `.all`
- `.cpuOnly`
- `.cpuAndGPU`
- `.cpuAndNeuralEngine`

This app defaulted to `.all`.

## Debug Video Replay

The production runner now supports a second frame source besides live capture:

- live rear camera
- debug video replay from a local movie file

Recommended pattern for reuse:

1. Keep one shared frame bus for all inference workers.
2. Feed that bus from either:
   - `CameraService` for live capture
   - `DebugVideoFrameSource` for deterministic replay
3. Keep the task engines and inference workers unaware of where frames came from.

This is useful for:

- debugging task logic on repeatable footage
- validating model parsing without setting up a live scene every time
- regression testing overlay and scoring behavior

The current implementation uses `AVAssetReader` to decode video frames and
publishes them back into the same `CameraFrameBus` used by live capture.

Bundled debug videos are expected under:

- `DebugVideos/`

The runtime scans that folder first, then falls back to a broader bundle scan
if Xcode flattened the files during copying.

### Embedded debug video mapping

The current app also links bundled videos to tasks by filename heuristics.

Examples:

- `keylock1.mp4` -> `KeyLock`
- `tip pos 1.mp4` -> `Tip Positioning`
- `rubber band.mp4` -> `Rubber Band`
- `springs.mp4` -> `Springs Suturing`

This allows the always-on preview stage to filter the embedded video picker to
the videos most likely to match the current task while still falling back to
all bundled videos if no filename match is found.

### Preview architecture

Preview ownership is screen-level rather than app-global:

- `Hub` shows a compact preview/status card
- `TaskRunner` owns the full-size active run preview

During an active run, the runner uses a focus-oriented full-screen layout with
controls collapsed by default and reopenable on demand.

Live camera preview and debug video preview still share the same inference bus,
but debug video frame decoding is streamed in a background task rather than
preloading every frame on the main actor. The visual player also loops the
selected embedded video until the trainer stops, resets, or exits the run.

## Ultralytics YOLO Output Handling

### Observed output type

Vision did not return `VNRecognizedObjectObservation`.
Instead it returned `VNCoreMLFeatureValueObservation` with:

- feature name like `var_1440`
- `MLMultiArray` shape `1 x 300 x 6`

That implies the exported model was already doing most of the post-processing and exposing one row per detection.

### Detection row interpretation

The rows were treated as:

`[x1, y1, x2, y2, confidence, classIndex]`

This worked for the model used in this project.

### Label extraction

Ultralytics class names were present in model metadata under creator-defined metadata, for example:

`names = "{0: 'Tip', 1: 'manual'}"`

The app parsed that string with regex and built `[Int: String]`.

If you reuse this elsewhere, do not hardcode class labels if metadata is present.

## Camera Architecture

## Stable setup

Stable:

- one `AVCaptureSession`
- one back `builtInLiDARDepthCamera`
- one synchronized video output
- one synchronized depth output

Unstable in this project:

- separate RGB back camera plus separate LiDAR session
- front camera PiP on top of the stable LiDAR synchronized graph
- repeated experiments with `AVCaptureMultiCamSession` for back + front + LiDAR

### Why LiDAR camera was chosen as the single source

`builtInLiDARDepthCamera` delivers:

- a YUV video stream
- a matched depth stream

That let the app use a single camera source for both:

- detection
- depth lookup

This avoided alignment problems between different camera devices and avoided unsupported multi-camera graphs.

## Synchronized Video + Depth

The correct pattern was:

```swift
videoOutput = AVCaptureVideoDataOutput()
depthOutput = AVCaptureDepthDataOutput()

let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
synchronizer.setDelegate(delegate, queue: synchronizerQueue)
```

Then in the synchronizer callback:

- get synchronized video sample buffer
- get synchronized depth data
- ignore dropped frames
- feed video into YOLO
- keep depth frame for preview and distance sampling

This was better than trying to consume unsynchronized video and depth outputs independently.

## LiDAR Device Configuration

Before running the session, the app selected:

- a LiDAR video format that supports depth data
- a depth data format of `DepthFloat16` or `DepthFloat32`

Pattern:

```swift
let preferredVideoFormat = device.formats.first { !$0.supportedDepthDataFormats.isEmpty }
let preferredDepthFormat = preferredVideoFormat?.supportedDepthDataFormats.first { ...DepthFloat16 or DepthFloat32... }
```

Then:

```swift
try device.lockForConfiguration()
device.activeFormat = preferredVideoFormat
device.activeDepthDataFormat = preferredDepthFormat
device.unlockForConfiguration()
```

Without explicit depth-capable format selection, LiDAR depth delivery may silently fail or stay stuck in a waiting state.

## Orientation Lessons

## Critical rule

Do not query UIKit view/window/scene properties from background queues.

Earlier versions did this:

- reading `view.window?.windowScene?.effectiveGeometry.interfaceOrientation`
- from camera/session queues

That caused Main Thread Checker violations.

### Final fix

The app keeps a main-thread orientation snapshot:

- update it from `viewDidLayoutSubviews`
- use that cached value from background capture/inference paths

That is the safe pattern to carry forward.

## Preview orientation

For preview:

- set preview layer rotation based on cached interface orientation
- do that on main thread

## Capture orientation

For outputs:

- set `videoRotationAngle` on the video/depth connections
- use cached interface orientation
- do not read UIKit state on the session queue

## Vision / EXIF orientation

For `VNImageRequestHandler`, the app passed an EXIF orientation derived from the same cached interface orientation.

This matters because:

- preview rotation
- capture connection rotation
- Vision image orientation

must be conceptually aligned, or boxes will drift, mirror, or rotate incorrectly.

## Bounding Box Coordinate System

This was one of the most important lessons from the app.

### Model-space boxes

The app normalized raw YOLO coordinates to `0...1` rectangles first.

If coordinates looked like pixels rather than normalized values, it divided by the model input size (`512` here).

### Preview-space mapping

Do not map boxes to screen space by naive multiplication:

```swift
x * viewWidth
y * viewHeight
```

That fails whenever preview uses aspect fill or crop.

### Correct mapping used here

The app converted to AV metadata coordinates and then asked the preview layer to do the final mapping:

```swift
let metadataRect = CGRect(
    x: 1 - rect.maxX,
    y: 1 - rect.minY - rect.height,
    width: rect.width,
    height: rect.height
)

let previewRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
```

This fixed:

- crop mismatch
- aspect-fill offset
- horizontal inversion

### Why `1 - rect.maxX` was needed

At one stage the boxes were horizontally opposite the object.
That meant the model/camera geometry was mirrored relative to the preview mapping.

The practical fix in this app was the metadata conversion above, especially:

`x: 1 - rect.maxX`

Carry this forward as a verified fix for this camera/model combination.

## Crop / Scale Mode

The Vision request used:

`request.imageCropAndScaleOption = .scaleFill`

That means the image fed into the model may be stretched to fit the model input rather than center-cropped.

Implication:

- if you change crop mode, you must revalidate box conversion
- do not assume a box transform survives changing `.scaleFill` to `.centerCrop`

## Drawing Boxes

Working pattern:

1. Clear overlay sublayers each frame.
2. Convert each normalized detection rect to preview coordinates.
3. Draw a `CAShapeLayer` border.
4. Draw a `CATextLayer` label above the box.

This is simple and fast enough for a benchmark/validation app.

## Latency And FPS

### Inference latency

Each model runtime measured:

- `startTime = CACurrentMediaTime()`
- run Vision request
- latency = elapsed milliseconds

This was shown in the timing label.

### FPS

FPS was estimated by:

- counting synchronized video frames
- measuring elapsed time over a half-second window
- `fps = frameCount / elapsed`

This is sufficient for a validation app.

## Depth Preview

Depth preview was built by:

1. converting depth data to `DepthFloat32`
2. scanning the frame for min/max valid depth
3. dynamically normalizing depth values into grayscale

Dynamic normalization was important.
Earlier fixed-range normalization often made the depth image look blank depending on scene distance.

## Depth Orientation

The depth image required its own transform separate from preview rotation.

For this app/device combination, the depth image also needed an additional 180-degree correction.

That means depth orientation is not guaranteed to match preview orientation automatically.
Always validate depth view on-device.

## Depth Per Detection

### First version

The first version sampled only the box center.

That was noisy.

### Improved version

The better version computes median depth over a small patch around the box center.

That is more robust to:

- invalid depth pixels
- edge noise
- small alignment errors

This app stores a lightweight CPU copy of the latest depth frame and samples from it during detection parsing.

## Torch / Flash

For live video, use torch, not still-photo flash.

Pattern:

```swift
try device.lockForConfiguration()
device.torchMode = .on or .off
device.unlockForConfiguration()
```

Torch was only exposed for the back camera device.

## Practical Reuse Guidance

If you are rebuilding this in another app, prefer this order:

1. Bring up one stable LiDAR back-camera session.
2. Verify synchronized video + depth.
3. Verify YOLO inference on synchronized video.
4. Verify preview-to-box mapping.
5. Add depth-to-detection distance.
6. Only then experiment with extra camera streams like front PiP.

## What To Reuse Directly

These ideas are worth carrying into another app almost unchanged:

- runtime model discovery from bundled `.mlmodelc`
- explicit `MLModelConfiguration.computeUnits`
- metadata-driven class label extraction
- LiDAR single-source camera design
- `AVCaptureDataOutputSynchronizer` for video + depth
- preview-layer-based box coordinate conversion
- cached interface orientation, read on main thread only
- median depth sampling for detections

## What To Treat As Device-Specific

These may need revalidation on every new app/device:

- exact EXIF orientation mapping
- exact metadata-rect horizontal flip rule
- depth preview transform
- whether front PiP can coexist with LiDAR + inference
- whether `.scaleFill` remains the right crop mode

## Current File Of Record

All of the working implementation lives in:

- `mentor model tests/CameraViewController.swift`

This markdown is the transfer summary.
