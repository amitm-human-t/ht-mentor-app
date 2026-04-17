# AVFoundation / AVKit — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:avkit`
**Use when:** Camera session, audio players, debug video playback.

---

## Camera Service (Core/Camera/CameraService.swift)

```swift
@Observable @MainActor
final class CameraService {
    func startSession(frameBus: CameraFrameBus) async throws
    func stopSession()
    var isRunning: Bool { get }
}
```

Camera frames flow: `CameraService` → `CameraFrameBus` → `TaskInferenceWorker` + `InstrumentInferenceWorker`

## Debug Video Source (Core/Camera/DebugVideoFrameSource.swift)

Allows testing with pre-recorded `.mp4`/`.mov` files instead of live camera.
Video files live at `p2 app/DebugVideos/` (symlinked, NOT in git).

```swift
@Observable @MainActor
final class DebugVideoFrameSource {
    var selectedVideoURL: URL?
    func selectVideo(url: URL)
    func start(frameBus: CameraFrameBus) async throws
    func stop()
}
```

Selected via TrainerControlsPanel → "Preview Source" → "Debug Video" picker.

## Audio Service (Core/Audio/AudioService.swift)

Three independent players:

```swift
@Observable @MainActor
final class AudioService {
    // Background music (loops forever)
    func startBackgroundMusic(_ sound: SoundCatalog)
    func stopBackgroundMusic()

    // Callout queue (one at a time, no overlap)
    func queueCallout(_ sound: SoundCatalog)

    // Effect (highest priority, interrupts callout)
    func playEffect(_ sound: SoundCatalog)
}
```

## Sound Assets (Core/Assets/AssetCatalog.swift)

```swift
enum SoundCatalog {
    // Effects
    case success, success2, fail, finished, gameover

    // Background music
    case background1, background2

    // KeyLock callouts
    case keylock(Int)           // keylock(1)...keylock(13)

    // TipPositioning callouts (hand-specific)
    case tipLeft(Int)           // l1...l7
    case tipRight(Int)          // r1...r7
}
```

Sound files are at `sounds/` (symlinked into Xcode).

## Triggering Audio from Engines

Task engines emit `RunEvent` objects; the coordinator plays audio:

```swift
// In TaskStepOutput.events
enum RunEvent {
    case targetReached(TargetID)
    case audioCallout(SoundCatalog)
    case taskCompleted
}

// RunnerCoordinator processes events after each tick()
for event in latestOutput.events {
    if case .audioCallout(let sound) = event {
        appModel.audioService.queueCallout(sound)
    }
}
```

## Camera Preview (Core/Camera/CameraPreviewView.swift)

Wraps `AVCaptureVideoPreviewLayer` in a `UIViewRepresentable`.
Exposes `PreviewCoordinate` for YOLO coordinate conversion.

```swift
CameraPreviewView(
    session: cameraService.captureSession,
    previewCoordinate: previewCoordinate
)
```

## Permissions

Camera requires `NSCameraUsageDescription` in `Info.plist`.
Check via `PermissionCenter` before starting session:
```swift
let permissions = await permissionCenter.refresh()
guard permissions.camera == .authorized else { ... }
```
