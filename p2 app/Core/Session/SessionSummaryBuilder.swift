import Foundation

enum SessionSummaryBuilder {
    static func makeSummary(
        task: TaskDefinition,
        mode: TaskMode,
        startedAt: Date,
        endedAt: Date,
        output: TaskStepOutput,
        handXConnected: Bool,
        thermalStateName: String = "nominal"
    ) -> RunSummaryDraft {
        let accuracy: Double? = output.progress.total > 0
            ? Double(output.progress.completed) / Double(output.progress.total) * 100
            : nil

        let eventRecords = output.events.map { event in
            RunEventRecord(name: event.name, timestamp: event.timestamp, payload: event.payload)
        }

        let payload = RunPayload(
            statusText: output.statusText,
            targetInfo: output.targetInfo,
            thermalState: thermalStateName,
            events: eventRecords
        )

        return RunSummaryDraft(
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
            accuracyPercent: accuracy,
            handXUsed: handXConnected,
            summaryPayload: payload
        )
    }
}
