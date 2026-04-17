# Swift Testing — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swift-testing`
**Use when:** Task engine tests, BLE decoder tests, SwiftData repository tests.

---

## Test Target

```
HandXPadTests/
├── Tasks/
│   ├── KeyLockTaskEngineTests.swift
│   ├── TipPositioningTaskEngineTests.swift
│   ├── RubberBandTaskEngineTests.swift
│   ├── SpringsSuturingTaskEngineTests.swift
│   └── ManualScoringEngineTests.swift
├── BLE/
│   └── HandXPacketDecoderTests.swift
└── Storage/
    └── RepositoryTests.swift
```

## Swift Testing Syntax (NOT XCTest)

```swift
import Testing
@testable import p2_app

@Suite("KeyLock Task Engine")
struct KeyLockTaskEngineTests {

    @Test("first detection advances target")
    func firstDetectionAdvancesTarget() {
        var engine = KeyLockTaskEngine()
        engine.configure(TaskConfig(task: .keyLock, mode: .guided, targetCount: 5))
        engine.start()

        let inputs = TaskInputs.mock(keyDetected: true, slotDetected: true)
        let output = engine.step(inputs: inputs)

        #expect(output.progress.completed == 1)
        #expect(output.score > 0)
    }

    @Test("mark failure reduces score")
    func markFailureReducesScore() throws {
        var engine = KeyLockTaskEngine()
        engine.configure(TaskConfig(task: .keyLock, mode: .guided, targetCount: 5))
        engine.start()

        // Get initial score by completing a target
        let inputs1 = TaskInputs.mock(keyDetected: true, slotDetected: true)
        let output1 = engine.step(inputs: inputs1)
        let scoreAfterSuccess = output1.score

        let inputs2 = TaskInputs.mock(trainerActions: [.init(kind: .markFailure, timestamp: 0)])
        let output2 = engine.step(inputs: inputs2)

        #expect(output2.score < scoreAfterSuccess)
    }
}
```

## TaskInputs Mock Helper

```swift
extension TaskInputs {
    static func mock(
        elapsed: TimeInterval = 0,
        keyDetected: Bool = false,
        slotDetected: Bool = false,
        tipDetected: Bool = false,
        trainerActions: [TrainerAction] = []
    ) -> TaskInputs {
        TaskInputs(
            elapsed: elapsed,
            handXSample: HandXSample(),
            instrumentTip: tipDetected ? CGPoint(x: 0.5, y: 0.5) : nil,
            taskDetections: makeDetections(key: keyDetected, slot: slotDetected),
            trainerActions: trainerActions,
            inferenceInfo: .mock
        )
    }
}
```

## SwiftData In-Memory Tests

```swift
@Suite("User Repository")
struct RepositoryTests {
    var container: ModelContainer!
    var context: ModelContext!

    init() throws {
        container = try ModelContainer(
            for: UserRecord.self, RunSummaryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    @Test("creates and fetches user")
    func createAndFetchUser() throws {
        let repo = UserRepository(context: context)
        let user = UserRecord(id: UUID(), displayName: "Test", dominantHand: .right, createdAt: .now)
        try repo.save(user)

        let fetched = try repo.fetchAll()
        #expect(fetched.count == 1)
        #expect(fetched[0].displayName == "Test")
    }
}
```

## Key Testing Principles

- Task engines are pure: `struct` or `final class` with value-type inputs → deterministic
- No mocking needed for engine tests — just construct `TaskInputs` directly
- BLE decoder tests: pure `Data` → `HandXSample` function, no CBCentral needed
- SwiftData tests: always use in-memory container
- Run engines headlessly (no camera, no inference) for unit tests
