# SwiftData — HandX Project Reference

**Plugin:** `ios-ai-ml-skills:swiftdata`
**Use when:** Reading/writing users, run summaries, curriculum records; adding new @Model types.

---

## Models (Core/Storage/StorageModels.swift)

```swift
@Model final class UserRecord {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var dominantHand: DominantHand
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var runSummaries: [RunSummaryRecord]
}

@Model final class RunSummaryRecord {
    @Attribute(.unique) var id: UUID
    var taskID: String
    var mode: String
    var score: Int
    var duration: TimeInterval
    var startedAt: Date
    var handXConnected: Bool
    var summaryPayloadJSON: Data?
    var user: UserRecord?
}

@Model final class CurriculumRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var stepsJSON: Data
    var createdAt: Date
}
```

## Querying in Views

```swift
// Live list — always sorted
@Query(sort: \RunSummaryRecord.startedAt, order: .reverse)
private var allRuns: [RunSummaryRecord]

// Filtered + sorted
@Query(
    filter: #Predicate<RunSummaryRecord> { $0.taskID == "keyLock" },
    sort: \RunSummaryRecord.score, order: .reverse
)
private var keyLockRuns: [RunSummaryRecord]

// Dynamic filter (init injection)
struct UserRunsView: View {
    @Query private var runs: [RunSummaryRecord]

    init(userID: UUID) {
        _runs = Query(
            filter: #Predicate<RunSummaryRecord> { $0.user?.id == userID },
            sort: \RunSummaryRecord.startedAt, order: .reverse
        )
    }
}
```

## CRUD Operations

```swift
@Environment(\.modelContext) private var modelContext

// Create
let user = UserRecord(id: UUID(), displayName: "Trainee", dominantHand: .right, createdAt: .now)
modelContext.insert(user)
try? modelContext.save()   // or rely on autosave

// Update — just mutate
user.displayName = "Dr. Smith"

// Delete
modelContext.delete(user)

// Bulk delete
try? modelContext.delete(model: RunSummaryRecord.self,
    where: #Predicate { $0.score == 0 })
```

## Background Work

```swift
@ModelActor
actor DataImporter {
    func importRuns(_ drafts: [RunSummaryDraft]) throws {
        for draft in drafts {
            let record = RunSummaryRecord(...)
            modelContext.insert(record)
        }
        try modelContext.save()  // always explicit save in @ModelActor
    }
}
```

## Adding a New @Model

1. Add `@Model final class Foo { ... }` to `StorageModels.swift`
2. Add `Foo.self` to the `.modelContainer(for: [...])` in `p2_appApp.swift`
3. Create or update `FooRepository` in `Repositories.swift`
4. If schema changes: add `VersionedSchema` + `SchemaMigrationPlan` (see `swiftdata-advanced.md`)

**⚠️ Xcode Action Required:** After adding a new model, the human must add `Foo.self` to the modelContainer in Xcode.

## Rules

- Never pass `@Model` objects across actors — use `PersistentIdentifier`
- `ModelContext` must stay on the actor that created it
- All `@Model` classes are `@MainActor`-safe via the main context
- Use `.externalStorage` for large `Data` blobs (e.g., video thumbnails)
