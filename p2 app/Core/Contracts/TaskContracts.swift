import Foundation
import CoreGraphics
import SwiftUI
import simd

enum TaskIdentifier: String, Codable, Hashable, CaseIterable {
    case keyLock
    case tipPositioning
    case rubberBand
    case springsSuturing
    case manualScoring
}

extension TaskIdentifier {
    var embeddedVideoKeywords: [String] {
        switch self {
        case .keyLock:
            return ["keylock", "key_lock", "key"]
        case .tipPositioning:
            return ["tippos", "tip_positioning", "tippositioning", "tip pos", "tip"]
        case .rubberBand:
            return ["rubberband", "rubber_band", "rubber band"]
        case .springsSuturing:
            return ["springs", "spring", "suturing"]
        case .manualScoring:
            return []
        }
    }
}

enum TaskMode: String, Codable, Hashable, CaseIterable {
    case guided
    case sprint
    case lockedSprint
    case freestyle
    case tutorial
    case timer
    case survival
    case manual
}

struct TaskDefinition: Hashable, Codable, Identifiable {
    let id: TaskIdentifier
    let title: String
    let subtitle: String
    let supportedModes: [TaskMode]

    static let all: [TaskDefinition] = [
        .init(id: .keyLock, title: "KeyLock", subtitle: "Precision lock targeting", supportedModes: [.guided, .sprint, .lockedSprint]),
        .init(id: .tipPositioning, title: "Tip Positioning", subtitle: "Lateral targeting and callouts", supportedModes: [.guided, .sprint, .lockedSprint]),
        .init(id: .rubberBand, title: "Rubber Band", subtitle: "Elastic control under motion", supportedModes: [.guided, .sprint]),
        .init(id: .springsSuturing, title: "Springs Suturing", subtitle: "Loop and pole coordination", supportedModes: [.guided, .sprint]),
        .init(id: .manualScoring, title: "Manual Scoring", subtitle: "Trainer-driven event capture", supportedModes: [.manual])
    ]
}

struct TaskConfig: Hashable, Sendable {
    let task: TaskIdentifier
    let mode: TaskMode
    let targetCount: Int
    let dominantHand: DominantHand

    init(task: TaskIdentifier, mode: TaskMode, targetCount: Int, dominantHand: DominantHand = .right) {
        self.task = task
        self.mode = mode
        self.targetCount = targetCount
        self.dominantHand = dominantHand
    }
}

struct TrainerAction: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case skipTarget
        case markSuccess
        case markFailure
        case keyDropped
    }

    let kind: Kind
    let timestamp: TimeInterval
}

struct TaskInputs: Sendable {
    let elapsed: TimeInterval
    let handXSample: HandXSample
    let instrumentTip: InstrumentTipPayload?
    let taskDetections: [TaskDetection]
    let trainerActions: [TrainerAction]
    let inferenceInfo: InferenceStatus
}

struct TaskStepOutput: Sendable {
    let statusText: String
    let score: Int
    let targetInfo: String
    let progress: ProgressSnapshot
    let events: [RunEvent]
    let overlayPayload: OverlayPayload
}

struct ProgressSnapshot: Sendable {
    let completed: Int
    let total: Int
}

struct OverlayPayload: Sendable {
    var elements: [OverlayElement]

    static let empty = OverlayPayload(elements: [])
}

enum OverlayColor: String, Sendable, Hashable, CaseIterable {
    case green, cyan, orange, yellow, red, teal, white, pink, amber

    var swiftUIColor: Color {
        switch self {
        case .green:  return .hxSuccess
        case .cyan:   return .hxCyan
        case .orange: return Color(red: 1.0, green: 0.55, blue: 0.0)
        case .yellow: return .hxAmber
        case .red:    return .hxDanger
        case .teal:   return Color(red: 0.2, green: 0.85, blue: 0.75)
        case .white:  return .white
        case .pink:   return Color(red: 1.0, green: 0.30, blue: 0.65)
        case .amber:  return .hxWarning
        }
    }
}

enum OverlayElement: Sendable, Hashable {
    case box(CGRect, label: String, color: OverlayColor = .cyan)
    case line(CGPoint, CGPoint, label: String?)
    case target(CGPoint, radius: CGFloat, label: String)
}

struct RunEvent: Hashable, Sendable {
    let name: String
    let timestamp: TimeInterval
    let payload: [String: String]
}

struct TaskDetection: Identifiable, Hashable, Sendable {
    let id: UUID
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

struct InstrumentTipPayload: Hashable, Sendable {
    let location: CGPoint
    let confidence: Float
}

struct InferenceStatus: Hashable, Sendable {
    let taskModelLoaded: Bool
    let instrumentModelLoaded: Bool
    let taskOutputNames: [String]
    let taskDetectionCount: Int
    let instrumentTipDetected: Bool
}

protocol TaskEngine: Sendable {
    mutating func start()
    mutating func pause()
    mutating func reset()
    mutating func configure(_ config: TaskConfig)
    mutating func step(inputs: TaskInputs) -> TaskStepOutput
}

struct PlaceholderTaskEngine: TaskEngine {
    private var config: TaskConfig?

    mutating func start() {}
    mutating func pause() {}
    mutating func reset() {}
    mutating func configure(_ config: TaskConfig) {
        self.config = config
    }

    mutating func step(inputs: TaskInputs) -> TaskStepOutput {
        let targetCount = config?.targetCount ?? 10
        let progress = min(targetCount, Int(inputs.elapsed / 5))
        return TaskStepOutput(
            statusText: inputs.handXSample.connected ? "Ready for live evaluation" : "Running without HandX",
            score: progress * 10,
            targetInfo: "Shell runner active",
            progress: ProgressSnapshot(completed: progress, total: targetCount),
            events: [],
            overlayPayload: .empty
        )
    }
}
