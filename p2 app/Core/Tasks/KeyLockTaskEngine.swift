import Foundation
import CoreGraphics

/// KeyLock V2-oriented state machine:
/// - dual key flow (key1 + key2)
/// - active-key guidance (one key/move at a time)
/// - occupied-slot protection
/// - slot-window + hold-time acceptance before progression
/// - optional debug image-processing overlay payload
struct KeyLockTaskEngine: TaskEngine {
    private enum KeyID: String, CaseIterable {
        case key1
        case key2

        var other: KeyID { self == .key1 ? .key2 : .key1 }
    }

    private struct KeyState {
        var sequence: [Int] = []
        var index: Int = 0
        var holdStart: TimeInterval?

        var target: Int? {
            guard index >= 0 && index < sequence.count else { return nil }
            return sequence[index]
        }

        var completed: Bool { target == nil }
    }

    private var config: TaskConfig?
    private var keyStates: [KeyID: KeyState] = [:]
    private var activeKey: KeyID = .key1
    private var completedSlots: Set<Int> = []
    private var score = 0
    private var drops = 0
    private var completedTargets = 0
    private var processedActionTimestamps: Set<TimeInterval> = []

    private let rightExcluded: Set<Int> = [2, 5, 6]
    private let leftExcluded: Set<Int> = [9, 11, 12]

    mutating func start() {}
    mutating func pause() {}

    mutating func reset() {
        rebuildKeySequences()
        activeKey = .key1
        completedSlots = []
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
        let configuredTargetCount = config?.targetCount ?? 10
        var events: [RunEvent] = []

        let slotDetections = inputs.taskDetections.filter { $0.label == "slot" }
        let inWindows = inputs.taskDetections.filter { $0.label == "in" }
        let slotRects = (!slotDetections.isEmpty ? slotDetections : inWindows)
            .map(\.boundingBox)
        let slotMap = assignSlotIDs(slotRects: slotRects)

        let slotOverlapThreshold = CGFloat(UserDefaultsStore.keyLockSlotOverlapThreshold)
        let holdDurationSeconds = TimeInterval(UserDefaultsStore.keyLockHoldDurationSeconds)
        let acceptanceConfidence = UserDefaultsStore.keyLockAcceptanceConfidence

        let key1Detection = bestDetection(label: "key1", from: inputs.taskDetections)
            ?? bestDetection(label: "key", from: inputs.taskDetections)
        let key2Detection = bestDetection(label: "key2", from: inputs.taskDetections)

        for action in inputs.trainerActions where !processedActionTimestamps.contains(action.timestamp) {
            processedActionTimestamps.insert(action.timestamp)
            switch action.kind {
            case .skipTarget:
                advanceTarget(for: activeKey, reason: "skip_target", events: &events, timestamp: action.timestamp, awardPoints: false)
            case .markSuccess:
                advanceTarget(for: activeKey, reason: "manual_success", events: &events, timestamp: action.timestamp, awardPoints: true)
            case .keyDropped:
                drops += 1
                score = max(0, score - 5)
                events.append(.init(name: "key_dropped", timestamp: action.timestamp, payload: [
                    "key": activeKey.rawValue,
                    "target": "\(currentTarget(for: activeKey) ?? 0)"
                ]))
            case .markFailure:
                score = max(0, score - 2)
                events.append(.init(name: "manual_failure", timestamp: action.timestamp, payload: [
                    "key": activeKey.rawValue,
                    "target": "\(currentTarget(for: activeKey) ?? 0)"
                ]))
            }
        }

        if let target = currentTarget(for: activeKey),
           !completedSlots.contains(target),
           let targetRect = slotMap[target],
           let activeDetection = (activeKey == .key1 ? key1Detection : key2Detection) {

            let activeBox = activeDetection.boundingBox
            let targetOverlap = overlapRatio(activeBox, targetRect)
            let inWindow = inWindows.contains { overlapRatio(activeBox, $0.boundingBox) >= slotOverlapThreshold }
            let confidenceOkay = activeDetection.confidence >= acceptanceConfidence
            let shouldAdvance = targetOverlap >= slotOverlapThreshold && inWindow && confidenceOkay

            if shouldAdvance {
                if keyStates[activeKey]?.holdStart == nil {
                    keyStates[activeKey]?.holdStart = inputs.elapsed
                }
                let heldFor = inputs.elapsed - (keyStates[activeKey]?.holdStart ?? inputs.elapsed)
                if heldFor >= holdDurationSeconds {
                    advanceTarget(for: activeKey, reason: "slot_validated", events: &events, timestamp: inputs.elapsed, awardPoints: true)
                }
            } else {
                keyStates[activeKey]?.holdStart = nil
            }
        }

        let overlays = inputs.taskDetections.map { detection in
            OverlayElement.box(detection.boundingBox, label: "\(detection.label) \(Int(detection.confidence * 100))%")
        }

        var guidance: [OverlayElement] = []
        if let activeTarget = currentTarget(for: activeKey),
           let targetRect = slotMap[activeTarget] {
            let activeBox = (activeKey == .key1 ? key1Detection : key2Detection)?.boundingBox
            if let activeBox {
                guidance.append(.line(
                    CGPoint(x: activeBox.midX, y: activeBox.midY),
                    CGPoint(x: targetRect.midX, y: targetRect.midY),
                    label: "\(activeKey.rawValue.uppercased()) → #\(activeTarget)"
                ))
            }
            guidance.append(.target(
                CGPoint(x: targetRect.midX, y: targetRect.midY),
                radius: max(0.02, min(targetRect.width, targetRect.height) * 0.45),
                label: "#\(activeTarget)"
            ))
        }

        var debugElements: [OverlayElement] = []
        for (slotID, rect) in slotMap {
            let color: OverlayColor = completedSlots.contains(slotID) ? .green : .amber
            debugElements.append(.box(rect, label: "slot #\(slotID)", color: color))
        }
        if let key1Detection {
            debugElements.append(.box(key1Detection.boundingBox, label: "key1", color: .yellow))
        }
        if let key2Detection {
            debugElements.append(.box(key2Detection.boundingBox, label: "key2", color: .orange))
        }

        let status = inputs.inferenceInfo.taskModelLoaded
            ? "KeyLockV2 • active \(activeKey.rawValue.uppercased()) • detections \(inputs.inferenceInfo.taskDetectionCount)"
            : "KeyLockV2 shell active while model outputs are warming up"

        let k1Done = keyStates[.key1]?.index ?? 0
        let k2Done = keyStates[.key2]?.index ?? 0
        let sequenceTotal = (keyStates[.key1]?.sequence.count ?? 0) + (keyStates[.key2]?.sequence.count ?? 0)
        let totalTargets = max(configuredTargetCount, sequenceTotal)

        return TaskStepOutput(
            statusText: status,
            score: score,
            targetInfo: "K1 \(k1Done)/10 • K2 \(k2Done)/10 • Drops \(drops)",
            progress: ProgressSnapshot(completed: completedTargets, total: totalTargets),
            events: events,
            overlayPayload: OverlayPayload(elements: overlays + guidance),
            debugOverlayPayload: OverlayPayload(elements: debugElements)
        )
    }

    private mutating func advanceTarget(
        for key: KeyID,
        reason: String,
        events: inout [RunEvent],
        timestamp: TimeInterval,
        awardPoints: Bool
    ) {
        guard var state = keyStates[key], let target = state.target else { return }
        guard !completedSlots.contains(target) else { return }

        if awardPoints {
            score += 25
        }
        completedSlots.insert(target)
        completedTargets += 1
        events.append(.init(name: "target_completed", timestamp: timestamp, payload: [
            "key": key.rawValue,
            "target": "\(target)",
            "reason": reason
        ]))
        state.index += 1
        state.holdStart = nil
        keyStates[key] = state

        let next = key.other
        if keyStates[next]?.completed == false {
            activeKey = next
        }
    }

    private mutating func rebuildKeySequences() {
        let excluded = (config?.dominantHand == .left) ? leftExcluded : rightExcluded
        let allowed = Array(1...13).filter { !excluded.contains($0) }
        let seq1 = allowed.shuffled()
        let seq2 = shuffledWithoutIndexCollision(base: seq1, fallback: allowed)
        keyStates[.key1] = KeyState(sequence: seq1)
        keyStates[.key2] = KeyState(sequence: seq2)
    }

    private func shuffledWithoutIndexCollision(base: [Int], fallback: [Int]) -> [Int] {
        guard !base.isEmpty else { return [] }
        for _ in 0..<80 {
            let candidate = fallback.shuffled()
            if zip(base, candidate).allSatisfy({ $0 != $1 }) {
                return candidate
            }
        }
        return Array(base.dropFirst()) + [base.first!]
    }

    private func currentTarget(for key: KeyID) -> Int? {
        keyStates[key]?.target
    }

    private func bestDetection(label: String, from detections: [TaskDetection]) -> TaskDetection? {
        detections
            .filter { $0.label == label }
            .max(by: { $0.confidence < $1.confidence })
    }

    private func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let minArea = max(0.0001, min(lhs.width * lhs.height, rhs.width * rhs.height))
        return (intersection.width * intersection.height) / minArea
    }

    private func assignSlotIDs(slotRects: [CGRect]) -> [Int: CGRect] {
        let sorted = slotRects.sorted { lhs, rhs in
            if abs(lhs.midY - rhs.midY) > 0.03 {
                let invertY = UserDefaultsStore.keyLockInvertYOrdering
                return invertY ? (lhs.midY < rhs.midY) : (lhs.midY > rhs.midY)
            }
            return lhs.midX < rhs.midX
        }
        var mapping: [Int: CGRect] = [:]
        for (idx, rect) in sorted.enumerated() where idx < 13 {
            mapping[idx + 1] = rect
        }
        return mapping
    }
}
