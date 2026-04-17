import Foundation
import SwiftData

enum DominantHand: String, CaseIterable, Codable {
    case left
    case right
}

@Model
final class UserRecord {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var dominantHandRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(displayName: String, dominantHandRawValue: String) {
        self.id = UUID()
        self.displayName = displayName
        self.dominantHandRawValue = dominantHandRawValue
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
final class RunSummaryRecord {
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var taskID: String
    var mode: String
    var startedAt: Date
    var endedAt: Date
    var durationMS: Int
    var score: Int
    var completedTargets: Int
    var totalTargets: Int
    var accuracyPercent: Double?
    var handXUsed: Bool
    var summaryPayloadJSON: String

    init(draft: RunSummaryDraft) {
        self.id = draft.runID
        self.userID = draft.userID
        self.taskID = draft.taskID
        self.mode = draft.mode
        self.startedAt = draft.startedAt
        self.endedAt = draft.endedAt
        self.durationMS = draft.durationMS
        self.score = draft.score
        self.completedTargets = draft.completedTargets
        self.totalTargets = draft.totalTargets
        self.accuracyPercent = draft.accuracyPercent
        self.handXUsed = draft.handXUsed
        self.summaryPayloadJSON = (try? JSONEncoder().encode(draft.summaryPayload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

struct RunSummaryDraft: Hashable {
    let runID: UUID
    let userID: UUID?
    let taskID: String
    let mode: String
    let startedAt: Date
    let endedAt: Date
    let durationMS: Int
    let score: Int
    let completedTargets: Int
    let totalTargets: Int
    let accuracyPercent: Double?
    let handXUsed: Bool
    let summaryPayload: [String: String]

    var durationSeconds: Int { durationMS / 1000 }
    var taskTitle: String { TaskDefinition.all.first { $0.id.rawValue == taskID }?.title ?? taskID }
}
