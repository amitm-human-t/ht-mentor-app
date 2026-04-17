import Foundation
import CoreGraphics

// MARK: - RubberBandTaskEngine
//
// Detection classes: `bands`, `pin`, `ring`, `logo`
//
// Core mechanic per target:
//   The trainee loops a rubber band around a pin. Detection of `ring`
//   (band encircling a pin) for STABLE_FRAMES consecutive ticks confirms
//   placement and advances the target.
//
// Stability guard: prevents single-frame flicker from advancing the score.
//   `ring` must be visible for STABLE_FRAMES (3) consecutive ticks → target complete.
//   Any gap resets the counter back to 0.
//
// Occupancy semantics:
//   Each target represents one pin/band pairing. Once a target is confirmed,
//   that band position is "occupied" and cannot re-score. A separate counter
//   tracks total occupied pins for the overlay.

struct RubberBandTaskEngine: TaskEngine {

    private static let stableFramesRequired = 3

    // MARK: - State

    private var config: TaskConfig?
    private var currentTarget = 1
    private var score = 0
    private var completedTargets = 0
    private var processedActionTimestamps: Set<TimeInterval> = []

    /// Consecutive frames ring has been detected for the current target
    private var stableRingFrameCount = 0
    /// Consecutive frames `bands` has been detected (for engagement tracking)
    private var bandsPresentCount = 0

    // MARK: - Protocol

    mutating func start() {}
    mutating func pause() {}

    mutating func reset() {
        currentTarget = 1
        score = 0
        completedTargets = 0
        stableRingFrameCount = 0
        bandsPresentCount = 0
        processedActionTimestamps = []
    }

    mutating func configure(_ config: TaskConfig) {
        self.config = config
        reset()
    }

    mutating func step(inputs: TaskInputs) -> TaskStepOutput {
        let targetCount = config?.targetCount ?? 10
        var events: [RunEvent] = []

        // Trainer actions
        for action in inputs.trainerActions where !processedActionTimestamps.contains(action.timestamp) {
            processedActionTimestamps.insert(action.timestamp)
            switch action.kind {
            case .skipTarget:
                advanceTarget(reason: "skip", events: &events, timestamp: action.timestamp, pts: 0)
            case .markSuccess:
                advanceTarget(reason: "manual_success", events: &events, timestamp: action.timestamp, pts: 30)
            case .markFailure:
                score = max(0, score - 5)
                stableRingFrameCount = 0
                events.append(.init(name: "manual_failure", timestamp: action.timestamp,
                                    payload: ["target": "\(currentTarget)"]))
            case .keyDropped:
                break
            }
        }

        let labels = Set(inputs.taskDetections.map(\.label))

        // Band presence tracking (for status text)
        bandsPresentCount = labels.contains("bands") ? bandsPresentCount + 1 : 0

        // Ring stability guard
        if labels.contains("ring") {
            stableRingFrameCount += 1
            if stableRingFrameCount == 1 {
                events.append(.init(name: "ring_detected", timestamp: inputs.elapsed,
                                    payload: ["target": "\(currentTarget)", "stable": "0/\(Self.stableFramesRequired)"]))
            }
            if stableRingFrameCount >= Self.stableFramesRequired {
                // Stable ring confirmed — target complete
                advanceTarget(reason: "ring_stable", events: &events, timestamp: inputs.elapsed, pts: 30)
            }
        } else {
            if stableRingFrameCount > 0 {
                events.append(.init(name: "ring_lost", timestamp: inputs.elapsed,
                                    payload: ["target": "\(currentTarget)", "frames_seen": "\(stableRingFrameCount)"]))
            }
            stableRingFrameCount = 0
        }

        // Overlays
        let overlays: [OverlayElement] = inputs.taskDetections.map { det in
            let color: OverlayColor = switch det.label {
            case "ring":  .green
            case "pin":   .orange
            case "bands": .yellow
            default:      .white
            }
            return .box(det.boundingBox,
                        label: "\(det.label) \(Int(det.confidence * 100))%",
                        color: color)
        }

        // Status text
        let stableProgress = stableRingFrameCount > 0
            ? " · hold \(stableRingFrameCount)/\(Self.stableFramesRequired)"
            : ""
        let statusText = inputs.inferenceInfo.taskModelLoaded
            ? "RubberBand · target \(currentTarget)\(stableProgress)"
            : "RubberBand model warming up…"

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
        stableRingFrameCount = 0
        events.append(.init(name: "target_completed", timestamp: timestamp,
                            payload: ["target": "\(currentTarget)", "reason": reason]))
        currentTarget += 1
    }
}
