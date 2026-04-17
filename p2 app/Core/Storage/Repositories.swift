import Foundation
import SwiftData

@MainActor
final class UserRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchUsers() -> [UserRecord] {
        (try? modelContext.fetch(FetchDescriptor<UserRecord>(sortBy: [SortDescriptor(\.displayName)]))) ?? []
    }

    func insert(_ user: UserRecord) {
        modelContext.insert(user)
        try? modelContext.save()
    }

    func delete(_ user: UserRecord) {
        modelContext.delete(user)
        try? modelContext.save()
    }
}

@MainActor
final class RunSummaryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save(summary: RunSummaryDraft) {
        modelContext.insert(RunSummaryRecord(draft: summary))
        try? modelContext.save()
    }
}

@MainActor
final class LeaderboardRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func topRuns(limit: Int = 10) -> [RunSummaryRecord] {
        var descriptor = FetchDescriptor<RunSummaryRecord>(sortBy: [SortDescriptor(\.score, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
