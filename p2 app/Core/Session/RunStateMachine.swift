import Foundation

struct RunStateMachine: Equatable, Sendable {
    enum Phase: String, Sendable {
        case idle
        case running
        case paused
        case finished
        case error
    }

    private(set) var phase: Phase = .idle

    mutating func start() {
        phase = .running
    }

    mutating func pause() {
        phase = .paused
    }

    mutating func resume() {
        phase = .running
    }

    mutating func finish() {
        phase = .finished
    }

    mutating func fail() {
        phase = .error
    }

    mutating func reset() {
        phase = .idle
    }
}
