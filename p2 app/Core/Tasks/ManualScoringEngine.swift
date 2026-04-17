import Foundation
import CoreGraphics

// MARK: - ManualScoringEngine
//
// Pure trainer-driven scoring — no CV model required.
// All score/progress changes come exclusively from trainer panel actions.
//
// Trainer actions:
//   markSuccess  → +20 pts, advance target
//   markFailure  → −5 pts, no advance
//   skipTarget   → 0 pts, advance target
//   keyDropped   → treated as markFailure (−5 pts)
//
// The engine also surfaces whatever instrument-tip and task detections arrive
// (from the always-on models) as overlays, so the trainer gets visual feedback
// even though scores are fully manual.

struct ManualScoringEngine: TaskEngine {

    // MARK: - State

    private var config: TaskConfig?
    private var currentTarget = 1
    private var score = 0
    private var completedTargets = 0
    private var processedActionTimestamps: Set<TimeInterval> = []
    private var successCount = 0
    private var failureCount = 0

    // MARK: - Protocol

    mutating func start() {}
    mutating func pause() {}

    mutating func reset() {
        currentTarget = 1
        score = 0
        completedTargets = 0
        processedActionTimestamps = []
        successCount = 0
        failureCount = 0
    }

    mutating func configure(_ config: TaskConfig) {
        self.config = config
        reset()
    }

    mutating func step(inputs: TaskInputs) -> TaskStepOutput {
        let targetCount = config?.targetCount ?? 10
        var events: [RunEvent] = []

        // All scoring is trainer-driven
        for action in inputs.trainerActions where !processedActionTimestamps.contains(action.timestamp) {
            processedActionTimestamps.insert(action.timestamp)
            switch action.kind {
            case .markSuccess:
                score += 20
                successCount += 1
                events.append(.init(name: "manual_success", timestamp: action.timestamp,
                                    payload: ["target": "\(currentTarget)", "score_delta": "+20"]))
                advanceTarget(reason: "mark_success", events: &events, timestamp: action.timestamp)

            case .skipTarget:
                events.append(.init(name: "manual_skip", timestamp: action.timestamp,
                                    payload: ["target": "\(currentTarget)"]))
                advanceTarget(reason: "skip", events: &events, timestamp: action.timestamp)

            case .markFailure, .keyDropped:
                score = max(0, score - 5)
                failureCount += 1
                events.append(.init(name: "manual_failure", timestamp: action.timestamp,
                                    payload: ["target": "\(currentTarget)", "score_delta": "-5"]))
            }
        }

        // Pass-through overlays: instrument tip + any task detections
        var overlays: [OverlayElement] = []
        if let tip = inputs.instrumentTip {
            overlays.append(.target(tip.location, radius: 0.025, label: "Tip"))
        }
        overlays += inputs.taskDetections.map { det in
            .box(det.boundingBox,
                 label: "\(det.label) \(Int(det.confidence * 100))%",
                 color: .cyan)
        }

        let statusText = "Manual · target \(currentTarget) · ✓\(successCount) ✗\(failureCount)"

        return TaskStepOutput(
            statusText: statusText,
            score: score,
            targetInfo: "Target \(currentTarget) of \(targetCount) · Manual scoring",
            progress: ProgressSnapshot(completed: completedTargets, total: targetCount),
            events: events,
            overlayPayload: OverlayPayload(elements: overlays)
        )
    }

    // MARK: - Helpers

    private mutating func advanceTarget(
        reason: String,
        events: inout [RunEvent],
        timestamp: TimeInterval
    ) {
        completedTargets += 1
        events.append(.init(name: "target_completed", timestamp: timestamp,
                            payload: ["target": "\(currentTarget)", "reason": reason]))
        currentTarget += 1
    }
}
