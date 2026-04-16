import AVFoundation
import Foundation

actor CameraFrameBus {
    /// A single latest-frame payload shared by live camera capture and debug
    /// video replay. `CVPixelBuffer` is treated as trusted framework-owned data.
    struct Frame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
    }

    private(set) var latestPixelBuffer: CVPixelBuffer?
    private(set) var latestTimestamp: TimeInterval = 0
    private var continuations: [UUID: AsyncStream<Frame>.Continuation] = [:]

    /// Replaces any older frame so inference workers always consume the most
    /// recent sample rather than growing an unbounded queue.
    func publish(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        latestPixelBuffer = pixelBuffer
        latestTimestamp = timestamp
        let frame = Frame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        for continuation in continuations.values {
            continuation.yield(frame)
        }
    }

    func latestFrame() -> Frame? {
        guard let latestPixelBuffer else { return nil }
        return Frame(pixelBuffer: latestPixelBuffer, timestamp: latestTimestamp)
    }

    func subscribe() -> AsyncStream<Frame> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}
