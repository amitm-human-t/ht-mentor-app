# SwiftUI Animation — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swiftui-animation`
**Use when:** Counters, progress rings, BLE pulse dot, transitions, screen-to-screen zoom.

---

## Design Token Animations (Core/DesignSystem/DesignTokens.swift)

```swift
Animation.hxDefault   // .easeOut(duration: 0.2)
Animation.hxPanel     // .spring(response: 0.35, dampingFraction: 0.75)
Animation.hxModal     // .spring(response: 0.4, dampingFraction: 0.82)
```

Always prefer these tokens over ad-hoc durations.

## Score / Number Counter (HUD)

```swift
Text("\(score)")
    .font(.hxMonoDisplay)
    .contentTransition(.numericText(countsDown: false))
    .animation(.snappy, value: score)
```

## Progress Ring

```swift
Circle()
    .trim(from: 0, to: progress)   // CGFloat 0.0–1.0
    .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    .rotationEffect(.degrees(-90))
    .animation(.smooth, value: progress)
```

## BLE Pulse Dot (PhaseAnimator)

```swift
StatusDot(color: .hxSuccess, isActive: bleConnected)
// StatusDot uses PhaseAnimator internally — just pass isActive
```

Direct PhaseAnimator pattern:
```swift
PhaseAnimator([false, true], trigger: someID) { pulsed in
    Circle()
        .scaleEffect(pulsed ? 1.12 : 1.0)
        .opacity(pulsed ? 0.9 : 0.5)
} animation: { _ in .easeInOut(duration: 0.8) }
```

## Panel Slide Transition

```swift
// TrainerControlsPanel appearance
TrainerControlsPanel(...)
    .transition(.move(edge: .trailing).combined(with: .opacity))

// Trigger with design token
.animation(.hxPanel, value: isPanelVisible)
```

## Navigation Zoom (TaskPicker → TaskRunner)

```swift
// In TaskPickerView — source
@Namespace private var zoomNS

TaskCard(...)
    .matchedTransitionSource(id: task.id, in: zoomNS)

// In NavigationLink destination — TaskRunnerView
TaskRunnerView(...)
    .navigationTransition(.zoom(sourceID: task.id, in: zoomNS))
```

## Failure Banner (slide from top)

```swift
if let failure = coordinator.currentFailure {
    FailureBanner(failure: failure)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.hxDefault, value: coordinator.currentFailure != nil)
}
```

## BLE Reconnect Countdown Ring

```swift
// In BLEReconnectOverlay — countdown 10→0
Circle()
    .trim(from: 0, to: CGFloat(countdown) / 10.0)
    .stroke(Color.hxAmber, style: StrokeStyle(lineWidth: 6, lineCap: .round))
    .rotationEffect(.degrees(-90))
    .animation(.linear(duration: 1.0), value: countdown)
```

## Reduce Motion

Always respect reduced motion for non-functional animations:
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

withAnimation(reduceMotion ? .none : .hxPanel) {
    isPanelVisible.toggle()
}
```
