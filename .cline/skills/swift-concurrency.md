# Swift Concurrency — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swift-concurrency`
**Use when:** Inference workers, camera frame bus, run loop, any background processing.

---

## Actor Hierarchy in This Project

```
MainActor
├── AppModel (@Observable @MainActor)
├── RunnerCoordinator (@Observable @MainActor)
└── HandXBLEManager (@Observable @MainActor or actor)

Background actors
├── CameraFrameBus (actor)           — frame distribution
├── CoreMLModelRegistry (actor)      — model loading/inference
├── TaskInferenceWorker (actor)      — YOLO task detection
└── InstrumentInferenceWorker (actor) — instrument tip detection
```

## CameraFrameBus Pattern

```swift
actor CameraFrameBus {
    // Use bufferingNewest(1) — ALWAYS drop old frames, never queue
    private var continuation: AsyncStream<CVPixelBuffer>.Continuation?

    func subscribe() -> AsyncStream<CVPixelBuffer> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
        }
    }

    func publish(_ frame: CVPixelBuffer) {
        continuation?.yield(frame)
    }
}
```

## Inference Workers (self-scheduling)

```swift
actor TaskInferenceWorker {
    private(set) var latestSnapshot = TaskInferenceSnapshot(...)
    private var processingTask: Task<Void, Never>?

    func startProcessing(frameBus: CameraFrameBus) {
        processingTask = Task {
            for await frame in await frameBus.subscribe() {
                guard !Task.isCancelled else { break }
                latestSnapshot = await runInference(on: frame)
            }
        }
    }
    // RunnerCoordinator.tick() reads latestSnapshot synchronously — no await
}
```

## Run Loop (RunnerCoordinator)

```swift
// 100ms tick — reads actors synchronously, no awaits inside tick()
private func beginRunLoop() {
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
    // Read latest snapshots — no await, actors expose read-only computed props
    let taskSnap = taskInferenceWorker?.latestSnapshot ?? .empty
    let instrSnap = instrumentInferenceWorker?.latestSnapshot ?? .empty
    // Build inputs, step engine
    latestOutput = taskEngine.step(inputs: ...)
}
```

## Sendable Rules

- Never pass `@Model` objects across actors — use `PersistentIdentifier`
- `CVPixelBuffer` is NOT Sendable — wrap in `@unchecked Sendable` only when needed
- Task engine inputs (`TaskInputs`) must be `Sendable`
- Use `@MainActor` on any class that updates SwiftUI state

## Common Pattern: BLE 10s Countdown

```swift
// Structured Task with cancellation
var countdownTask: Task<Void, Never>?

func startCountdown() {
    countdownTask = Task { [weak self] in
        for remaining in stride(from: 9, through: 0, by: -1) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.disconnectCountdown = remaining
        }
        guard !Task.isCancelled else { return }
        // Timeout logic
    }
}

func cancelCountdown() {
    countdownTask?.cancel()
    countdownTask = nil
    disconnectCountdown = nil
}
```
