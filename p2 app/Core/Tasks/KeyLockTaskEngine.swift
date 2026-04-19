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

    private struct TrackedDetection {
        var detection: TaskDetection
        var lastSeen: TimeInterval
    }

    private var config: TaskConfig?
    private var keyStates: [KeyID: KeyState] = [:]
    private var activeKey: KeyID = .key1
    private var completedSlots: Set<Int> = []
    private var score = 0
    private var drops = 0
    private var completedTargets = 0
    private var processedActionTimestamps: Set<TimeInterval> = []
    private var key1Tracked: TrackedDetection?
    private var key2Tracked: TrackedDetection?
    private var lastStableSlotMap: [Int: CGRect] = [:]
    private var lastStableSlotMapTimestamp: TimeInterval?

    private let rightExcluded: Set<Int> = [2, 5, 6]
    private let leftExcluded: Set<Int> = [9, 11, 12]
    private let keyPersistenceSeconds: TimeInterval = 0.20
    private let slotMapPersistenceSeconds: TimeInterval = 0.25
    private let smoothingAlpha: CGFloat = 0.65

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
        key1Tracked = nil
        key2Tracked = nil
        lastStableSlotMap = [:]
        lastStableSlotMapTimestamp = nil
    }

    mutating func configure(_ config: TaskConfig) {
        self.config = config
        reset()
    }

    mutating func step(inputs: TaskInputs) -> TaskStepOutput {
        let configuredTargetCount = config?.targetCount ?? 10
        var events: [RunEvent] = []

        let inWindows = inputs.taskDetections.filter { $0.label == "in" }
        // KeyLockV2 slot discovery must treat both "slot" and "in" as slot candidates.
        // Using both avoids falling back when one label is partially missing per frame.
        let rawSlotRects = inputs.taskDetections
            .filter { $0.label == "slot" || $0.label == "in" }
            .map(\.boundingBox)
        let slotRects = deduplicateSlotRects(rawSlotRects)
        var slotMap = assignSlotIDs(slotRects: slotRects)

        if slotMap.count >= 10 {
            lastStableSlotMap = slotMap
            lastStableSlotMapTimestamp = inputs.elapsed
        } else if let lastTs = lastStableSlotMapTimestamp,
                  inputs.elapsed - lastTs <= slotMapPersistenceSeconds,
                  !lastStableSlotMap.isEmpty {
            slotMap = lastStableSlotMap
        }

        let slotOverlapThreshold = CGFloat(UserDefaultsStore.keyLockSlotOverlapThreshold)
        let holdDurationSeconds = TimeInterval(UserDefaultsStore.keyLockHoldDurationSeconds)
        let acceptanceConfidence = UserDefaultsStore.keyLockAcceptanceConfidence

        let rawKey1Detection = bestDetection(label: "key1", from: inputs.taskDetections)
            ?? bestDetection(label: "key", from: inputs.taskDetections)
        let rawKey2Detection = bestDetection(label: "key2", from: inputs.taskDetections)

        let key1Detection = stabilizedDetection(
            raw: rawKey1Detection,
            tracked: &key1Tracked,
            now: inputs.elapsed
        )
        let key2Detection = stabilizedDetection(
            raw: rawKey2Detection,
            tracked: &key2Tracked,
            now: inputs.elapsed
        )

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

    private func deduplicateSlotRects(_ rects: [CGRect]) -> [CGRect] {
        guard rects.count > 13 else { return rects }
        var kept: [CGRect] = []
        for rect in rects.sorted(by: { ($0.width * $0.height) > ($1.width * $1.height) }) {
            let overlapsExisting = kept.contains { overlapRatio(rect, $0) >= 0.70 }
            if !overlapsExisting {
                kept.append(rect)
            }
        }
        return kept
    }

    /// Assign KeyLockV2 slot IDs using explicit board semantics:
    /// - center slot is #13
    /// - left side bottom->top is #1...#6
    /// - right side bottom->top is #7...#12
    /// This matches the mentor-provided numbering (1/7 bottom, 6/12 top).
    private func assignSlotIDs(slotRects: [CGRect]) -> [Int: CGRect] {
        guard slotRects.count >= 13 else {
            // Fallback to deterministic generic ordering when detections are incomplete.
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

        // Center slot (#13): rectangle closest to the centroid of all slots.
        let centroid = CGPoint(
            x: slotRects.map(\.midX).reduce(0, +) / CGFloat(slotRects.count),
            y: slotRects.map(\.midY).reduce(0, +) / CGFloat(slotRects.count)
        )
        guard let centerRect = slotRects.min(by: {
            hypot($0.midX - centroid.x, $0.midY - centroid.y) < hypot($1.midX - centroid.x, $1.midY - centroid.y)
        }) else {
            return [:]
        }

        let nonCenter = slotRects.filter { $0 != centerRect }
        guard nonCenter.count >= 12 else { return [13: centerRect] }

        // Side split by X around center slot.
        let leftSide = nonCenter
            .filter { $0.midX < centerRect.midX }
            .sorted { $0.midX < $1.midX }
        let rightSide = nonCenter
            .filter { $0.midX >= centerRect.midX }
            .sorted { $0.midX > $1.midX }

        // Normalize to 6 per side (if one side has extras due to noisy detections).
        let leftSix = Array(leftSide.suffix(6))
        let rightSix = Array(rightSide.suffix(6))
        guard leftSix.count == 6, rightSix.count == 6 else {
            var mapping: [Int: CGRect] = [13: centerRect]
            let fallback = nonCenter.sorted { $0.midX < $1.midX }
            for (idx, rect) in fallback.enumerated() where idx < 12 {
                mapping[idx + 1] = rect
            }
            return mapping
        }

        let invertY = UserDefaultsStore.keyLockInvertYOrdering
        let leftBottomToTop = leftSix.sorted {
            invertY ? ($0.midY < $1.midY) : ($0.midY > $1.midY)
        }
        let rightBottomToTop = rightSix.sorted {
            invertY ? ($0.midY < $1.midY) : ($0.midY > $1.midY)
        }

        var mapping: [Int: CGRect] = [13: centerRect]
        for (idx, rect) in leftBottomToTop.enumerated() {
            mapping[idx + 1] = rect // 1...6
        }
        for (idx, rect) in rightBottomToTop.enumerated() {
            mapping[idx + 7] = rect // 7...12
        }
        return mapping
    }

    private func stabilizedDetection(
        raw: TaskDetection?,
        tracked: inout TrackedDetection?,
        now: TimeInterval
    ) -> TaskDetection? {
        if let raw {
            let blended: TaskDetection
            if let previous = tracked?.detection {
                blended = TaskDetection(
                    id: raw.id,
                    label: raw.label,
                    confidence: Float(
                        (CGFloat(previous.confidence) * (1.0 - smoothingAlpha))
                        + (CGFloat(raw.confidence) * smoothingAlpha)
                    ),
                    boundingBox: blend(previous.boundingBox, raw.boundingBox, alpha: smoothingAlpha)
                )
            } else {
                blended = raw
            }
            tracked = TrackedDetection(detection: blended, lastSeen: now)
            return blended
        }

        guard let tracked, now - tracked.lastSeen <= keyPersistenceSeconds else {
            tracked = nil
            return nil
        }
        return tracked.detection
    }

    private func blend(_ a: CGRect, _ b: CGRect, alpha: CGFloat) -> CGRect {
        let t = max(0, min(1, alpha))
        return CGRect(
            x: (a.origin.x * (1 - t)) + (b.origin.x * t),
            y: (a.origin.y * (1 - t)) + (b.origin.y * t),
            width: (a.size.width * (1 - t)) + (b.size.width * t),
            height: (a.size.height * (1 - t)) + (b.size.height * t)
        )
    }
}
