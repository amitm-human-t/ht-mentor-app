import Foundation
import CoreGraphics

// MARK: - SpringsSuturingTaskEngine
//
// Detection classes: `logo`, `spring`, `blue`, `loop`, `loop_needle`, `loop_thread`
//
// Core mechanic per target (one suturing cycle = one pole threading):
//   idle → loopVisible → needleIn → threadThrough → complete
//
//   idle:          waiting for `loop` to appear
//   loopVisible:   `loop` detected → waiting for `loop_needle`
//   needleIn:      `loop_needle` detected → waiting for `loop_thread`
//   threadThrough: `loop_thread` detected → cycle complete
//
// Drift guard:
//   If the expected detection class for the current phase is absent for
//   DRIFT_LIMIT consecutive ticks, the engine reverts one phase to prevent
//   false advancement from transient detections.
//
// Scoring: +10 per phase advance, +20 for full cycle completion (50 pts max/target)

struct SpringsSuturingTaskEngine: TaskEngine {

    // MARK: - Suture Sub-phase

    private enum SuturePhase: String, CaseIterable {
        case idle          // waiting for `loop`
        case loopVisible   // `loop` seen, waiting for `loop_needle`
        case needleIn      // `loop_needle` seen, waiting for `loop_thread`
        case threadThrough // `loop_thread` seen → complete this tick
    }

    private static let driftLimit = 5   // frames before reverting one phase

    // MARK: - State

    private var config: TaskConfig?
    private var currentTarget = 1
    private var suturePhase: SuturePhase = .idle
    private var score = 0
    private var completedTargets = 0
    private var processedActionTimestamps: Set<TimeInterval> = []
    private var driftFrameCount = 0     // frames current phase's expected class is absent

    // MARK: - Protocol

    mutating func start() {}
    mutating func pause() {}

    mutating func reset() {
        currentTarget = 1
        suturePhase = .idle
        score = 0
        completedTargets = 0
        driftFrameCount = 0
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
                advanceTarget(reason: "manual_success", events: &events, timestamp: action.timestamp, pts: 50)
            case .markFailure:
                score = max(0, score - 5)
                events.append(.init(name: "manual_failure", timestamp: action.timestamp,
                                    payload: ["target": "\(currentTarget)"]))
            case .keyDropped:
                break
            }
        }

        let labels = Set(inputs.taskDetections.map(\.label))

        // Advance through suture phases based on detections
        switch suturePhase {
        case .idle:
            if labels.contains("loop") {
                suturePhase = .loopVisible
                driftFrameCount = 0
                score += 10
                events.append(.init(name: "loop_detected", timestamp: inputs.elapsed,
                                    payload: ["target": "\(currentTarget)"]))
            }

        case .loopVisible:
            if labels.contains("loop_needle") {
                suturePhase = .needleIn
                driftFrameCount = 0
                score += 10
                events.append(.init(name: "needle_detected", timestamp: inputs.elapsed,
                                    payload: ["target": "\(currentTarget)"]))
            } else if !labels.contains("loop") {
                driftFrameCount += 1
                if driftFrameCount >= Self.driftLimit {
                    suturePhase = .idle
                    driftFrameCount = 0
                    events.append(.init(name: "drift_revert", timestamp: inputs.elapsed,
                                        payload: ["from": "loopVisible", "target": "\(currentTarget)"]))
                }
            } else {
                driftFrameCount = 0   // loop still present, not drifting
            }

        case .needleIn:
            if labels.contains("loop_thread") {
                suturePhase = .threadThrough
                driftFrameCount = 0
                score += 10
                events.append(.init(name: "thread_detected", timestamp: inputs.elapsed,
                                    payload: ["target": "\(currentTarget)"]))
                // Complete this target immediately
                advanceTarget(reason: "threaded", events: &events, timestamp: inputs.elapsed, pts: 20)
            } else if !labels.contains("loop_needle") {
                driftFrameCount += 1
                if driftFrameCount >= Self.driftLimit {
                    suturePhase = .loopVisible
                    driftFrameCount = 0
                    events.append(.init(name: "drift_revert", timestamp: inputs.elapsed,
                                        payload: ["from": "needleIn", "target": "\(currentTarget)"]))
                }
            } else {
                driftFrameCount = 0
            }

        case .threadThrough:
            // Should not linger here — advanceTarget resets to .idle
            suturePhase = .idle
            driftFrameCount = 0
        }

        // Overlays
        let overlays: [OverlayElement] = inputs.taskDetections.map { det in
            let color: OverlayColor = switch det.label {
            case "loop":        .cyan
            case "loop_needle": .green
            case "loop_thread": .teal
            case "spring":      .orange
            case "blue":        .yellow
            default:            .white
            }
            return .box(det.boundingBox,
                        label: "\(det.label) \(Int(det.confidence * 100))%",
                        color: color)
        }

        // Phase display
        let phaseHint: String = switch suturePhase {
        case .idle:          "Open loop"
        case .loopVisible:   "Thread needle through"
        case .needleIn:      "Pull thread through"
        case .threadThrough: "Complete"
        }

        let statusText = inputs.inferenceInfo.taskModelLoaded
            ? "Springs · target \(currentTarget) · \(phaseHint)"
            : "Springs model warming up…"

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
        suturePhase = .idle
        driftFrameCount = 0
    }
}
