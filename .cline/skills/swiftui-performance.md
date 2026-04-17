# SwiftUI Performance — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swiftui-performance`
**Use when:** Run loop re-render optimization, overlay drawing, thermal management.

---

## Render Isolation Strategy

The 100ms run loop ticks `RunnerCoordinator.latestOutput` constantly.
To avoid full-tree re-renders, keep views isolated by what they read:

| View | Reads only | Re-renders on |
|------|-----------|--------------|
| `RunnerHUDView` | `latestOutput.score`, `.progress`, `.targetInfo` | Score/progress changes |
| `PreviewOverlayView` | `latestOutput.overlayPayload` | Detection changes |
| `TrainerControlsPanel` | `stateMachine.phase`, `inputSource` | Phase transitions |
| `RunnerHUDView.timerSection` | Uses `TimelineView(.periodic)` | Every 1 second only |

**Key rule:** If a view doesn't read a property, `@Observable` granular tracking prevents re-renders.

## Detection Overlay (drawingGroup)

When detection count > 15, use `.drawingGroup()` to batch into a single Metal draw call:

```swift
PreviewOverlayView(payload: coordinator.latestOutput.overlayPayload)
    .drawingGroup(opaque: false)  // Only when box count > 15
```

## TimelineView for Timer (NOT a State timer)

```swift
// Use TimelineView for clock display — no @State ticker needed
TimelineView(.periodic(from: .now, by: 1)) { context in
    Text(elapsedString(at: context.date))
        .font(.hxMonoBody)
}
// This isolated subtree re-renders every second only
```

## Thermal Monitor (Core/Session/ThermalMonitor.swift)

```swift
@Observable @MainActor
final class ThermalMonitor {
    var thermalState: ProcessInfo.ThermalState = .nominal

    // On .critical: reduce inference to every other frame
    var shouldReduceInference: Bool {
        thermalState == .critical || thermalState == .serious
    }
}
```

Signal to workers:
```swift
// In RunnerCoordinator.tick()
if appModel.thermalMonitor.shouldReduceInference {
    tickCount += 1
    if tickCount % 2 != 0 { return }  // skip every other frame
}
```

## Lazy Loading

- All ScrollView content: `LazyVStack` / `LazyVGrid`
- Never place `GeometryReader` inside a lazy container
- User avatar colors: computed once via `abs(name.hashValue) % palette.count`

## Instruments Targets

For 60 FPS verification:
1. Xcode → Product → Profile → Metal System Trace
2. Watch "GPU Frame Time" — should stay < 16ms
3. Watch "CPU Usage" — main thread should stay < 50% during inference

## @Observable Granular Tracking Reminder

```swift
// These are independent re-render triggers in RunnerCoordinator
private(set) var latestOutput: TaskStepOutput     // changes every 100ms tick
private(set) var stateMachine: RunStateMachine    // changes on phase transitions
private(set) var currentFailure: RunnerFailure?   // rarely changes

// If a view only reads stateMachine.phase, it won't re-render on latestOutput changes
```
