import Foundation
import CoreGraphics

// MARK: - TipPositioningTaskEngine
//
// Detection classes: `tip`, `logo`, `slot`, `hover`, `in`
// Required transition per target: slot → hover → in
// Audio callouts: sounds/tip_positioning/{hand}{number}.mp3
//   hand = "l" (left) or "r" (right) from config.dominantHand
//   number = 1–7, cycling: target 1→"l1", 2→"l2", ..., 7→"l7", 8→"l1", etc.

struct TipPositioningTaskEngine: TaskEngine {

    // MARK: - Sub-phase per target

    private enum SubPhase: String {
        case waiting    // waiting for `slot` to appear
        case approached // `slot` seen — waiting for `hover`
        case inserting  // `hover` seen — waiting for `in`
    }

    // MARK: - State

    private var config: TaskConfig?
    private var currentTarget = 1
    private var subPhase: SubPhase = .waiting
    private var score = 0
    private var completedTargets = 0
    private var processedActionTimestamps: Set<TimeInterval> = []
    private var calloutEmittedForTarget = false  // emit callout only once per target

    // MARK: - Protocol

    mutating func start() {
        calloutEmittedForTarget = false
    }

    mutating func pause() {}

    mutating func reset() {
        currentTarget = 1
        subPhase = .waiting
        score = 0
        completedTargets = 0
        processedActionTimestamps = []
        calloutEmittedForTarget = false
    }

    mutating func configure(_ config: TaskConfig) {
        self.config = config
        reset()
    }

    mutating func step(inputs: TaskInputs) -> TaskStepOutput {
        let targetCount = config?.targetCount ?? 10
        var events: [RunEvent] = []

        // Process trainer actions (deduped by timestamp)
        for action in inputs.trainerActions where !processedActionTimestamps.contains(action.timestamp) {
            processedActionTimestamps.insert(action.timestamp)
            switch action.kind {
            case .skipTarget:
                advanceTarget(reason: "skip", events: &events, timestamp: action.timestamp, pts: 0)
            case .markSuccess:
                advanceTarget(reason: "manual_success", events: &events, timestamp: action.timestamp, pts: 25)
            case .markFailure:
                score = max(0, score - 2)
                events.append(.init(name: "manual_failure", timestamp: action.timestamp, payload: ["target": "\(currentTarget)"]))
            case .keyDropped:
                break   // not applicable to TipPositioning
            }
        }

        let labels = Set(inputs.taskDetections.map(\.label))

        // Emit callout audio event once when target becomes active
        if !calloutEmittedForTarget {
            calloutEmittedForTarget = true
            let file = calloutFile(for: currentTarget)
            events.append(.init(name: "audio_callout", timestamp: inputs.elapsed,
                                payload: ["dir": "tip_positioning", "file": file]))
        }

        // Detection-driven phase transitions
        switch subPhase {
        case .waiting:
            if labels.contains("slot") {
                subPhase = .approached
                events.append(.init(name: "slot_detected", timestamp: inputs.elapsed,
                                    payload: ["target": "\(currentTarget)"]))
            }

        case .approached:
            if labels.contains("hover") {
                subPhase = .inserting
                score += 10
                events.append(.init(name: "hover_detected", timestamp: inputs.elapsed,
                                    payload: ["target": "\(currentTarget)"]))
            }

        case .inserting:
            if labels.contains("in") {
                advanceTarget(reason: "inserted", events: &events, timestamp: inputs.elapsed, pts: 25)
            }
        }

        // Overlays — highlight tip and active target class with appropriate colors
        let overlays: [OverlayElement] = inputs.taskDetections.map { det in
            let color: OverlayColor = switch det.label {
            case "tip":   .cyan
            case "slot":  .orange
            case "hover": .yellow
            case "in":    .green
            default:      .white
            }
            return .box(det.boundingBox,
                        label: "\(det.label) \(Int(det.confidence * 100))%",
                        color: color)
        }

        // Phase status text
        let phaseHint: String = switch subPhase {
        case .waiting:    "Position tip near slot"
        case .approached: "Approach the slot target"
        case .inserting:  "Insert into the slot"
        }

        let statusText = inputs.inferenceInfo.taskModelLoaded
            ? "TipPos · target \(currentTarget) · \(phaseHint)"
            : "TipPos model warming up…"

        return TaskStepOutput(
            statusText: statusText,
            score: score,
            targetInfo: "Target \(currentTarget) of \(targetCount)",
            progress: ProgressSnapshot(completed: completedTargets, total: targetCount),
            events: events,
            overlayPayload: OverlayPayload(elements: overlays)
        )
    }

    // MARK: - Helpers

    private mutating func advanceTarget(
        reason: String,
        events: inout [RunEvent],
        timestamp: TimeInterval,
        pts: Int
    ) {
        score += pts
        completedTargets += 1
        events.append(.init(name: "target_completed", timestamp: timestamp,
                            payload: ["target": "\(currentTarget)", "reason": reason]))
        currentTarget += 1
        subPhase = .waiting
        calloutEmittedForTarget = false
    }

    /// Returns "l3" or "r5" etc. based on dominant hand + target index (cycles 1–7).
    private func calloutFile(for targetIndex: Int) -> String {
        let hand = (config?.dominantHand == .left) ? "l" : "r"
        let num = ((targetIndex - 1) % 7) + 1
        return "\(hand)\(num)"
    }
}
