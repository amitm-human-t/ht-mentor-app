import Foundation
import CoreGraphics

/// First-pass KeyLock state machine that preserves the documented transition
/// order and trainer actions while the full desktop parity logic is still being
/// ported.
struct KeyLockTaskEngine: TaskEngine {
    private enum Phase: String {
        case slot
        case inserted
        case locked
    }

    private var config: TaskConfig?
    private var currentTarget = 1
    private var currentPhase: Phase = .slot
    private var score = 0
    private var drops = 0
    private var completedTargets = 0
    private var processedActionTimestamps: Set<TimeInterval> = []

    mutating func start() {}
    mutating func pause() {}

    mutating func reset() {
        currentTarget = 1
        currentPhase = .slot
        score = 0
        drops = 0
        completedTargets = 0
        processedActionTimestamps = []
    }

    mutating func configure(_ config: TaskConfig) {
        self.config = config
        reset()
    }

    mutating func step(inputs: TaskInputs) -> TaskStepOutput {
        let targetCount = config?.targetCount ?? 10
        var events: [RunEvent] = []

        for action in inputs.trainerActions where !processedActionTimestamps.contains(action.timestamp) {
            processedActionTimestamps.insert(action.timestamp)
            switch action.kind {
            case .skipTarget:
                advanceTarget(reason: "skip_target", events: &events, timestamp: action.timestamp, awardPoints: false)
            case .markSuccess:
                advanceTarget(reason: "manual_success", events: &events, timestamp: action.timestamp, awardPoints: true)
            case .keyDropped:
                drops += 1
                score = max(0, score - 5)
                events.append(.init(name: "key_dropped", timestamp: action.timestamp, payload: ["target": "\(currentTarget)"]))
            case .markFailure:
                score = max(0, score - 2)
                events.append(.init(name: "manual_failure", timestamp: action.timestamp, payload: ["target": "\(currentTarget)"]))
            }
        }

        let labels = Set(inputs.taskDetections.map(\.label))
        // Preserve the required slot -> in -> locked progression so competitive
        // scoring only advances when the active target completes in order.
        if currentPhase == .slot && labels.contains("slot") {
            currentPhase = .inserted
            events.append(.init(name: "slot_detected", timestamp: inputs.elapsed, payload: ["target": "\(currentTarget)"]))
        }
        if currentPhase == .inserted && labels.contains("in") {
            currentPhase = .locked
            score += 10
            events.append(.init(name: "key_inserted", timestamp: inputs.elapsed, payload: ["target": "\(currentTarget)"]))
        }
        if currentPhase == .locked && labels.contains("locked") {
            advanceTarget(reason: "locked", events: &events, timestamp: inputs.elapsed, awardPoints: true)
        }

        let overlays = inputs.taskDetections.map { detection in
            OverlayElement.box(detection.boundingBox, label: "\(detection.label) \(Int(detection.confidence * 100))%")
        }

        let helper = OverlayElement.line(
            CGPoint(x: 0.2, y: 0.5),
            CGPoint(x: 0.8, y: 0.5),
            label: "Target \(currentTarget)"
        )

        let status = inputs.inferenceInfo.taskModelLoaded
            ? "KeyLock target \(currentTarget) • phase \(currentPhase.rawValue) • detections \(inputs.inferenceInfo.taskDetectionCount)"
            : "KeyLock shell active while model outputs are warming up"

        return TaskStepOutput(
            statusText: status,
            score: score,
            targetInfo: "Target \(currentTarget) of \(targetCount) • Drops \(drops)",
            progress: ProgressSnapshot(completed: completedTargets, total: targetCount),
            events: events,
            overlayPayload: OverlayPayload(elements: overlays + [helper])
        )
    }

    private mutating func advanceTarget(
        reason: String,
        events: inout [RunEvent],
        timestamp: TimeInterval,
        awardPoints: Bool
    ) {
        if awardPoints {
            score += 25
        }
        completedTargets += 1
        events.append(.init(name: "target_completed", timestamp: timestamp, payload: [
            "target": "\(currentTarget)",
            "reason": reason
        ]))
        currentTarget += 1
        currentPhase = .slot
    }
}
