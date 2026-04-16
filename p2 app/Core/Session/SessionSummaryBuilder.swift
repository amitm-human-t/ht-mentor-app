import Foundation

enum SessionSummaryBuilder {
    static func makeSummary(
        task: TaskDefinition,
        mode: TaskMode,
        startedAt: Date,
        endedAt: Date,
        output: TaskStepOutput,
        handXConnected: Bool
    ) -> RunSummaryDraft {
        RunSummaryDraft(
            runID: UUID(),
            userID: nil,
            taskID: task.id.rawValue,
            mode: mode.rawValue,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMS: Int(endedAt.timeIntervalSince(startedAt) * 1000),
            score: output.score,
            completedTargets: output.progress.completed,
            totalTargets: output.progress.total,
            accuracyPercent: nil,
            handXUsed: handXConnected,
            summaryPayload: [
                "statusText": output.statusText,
                "targetInfo": output.targetInfo
            ]
        )
    }
}
