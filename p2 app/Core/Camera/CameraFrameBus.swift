import AVFoundation
import Foundation

actor CameraFrameBus {
    /// A single latest-frame payload shared by live camera capture and debug
    /// video replay. `CVPixelBuffer` is treated as trusted framework-owned data.
    struct Frame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
        /// EXIF orientation matching the current device/interface orientation.
        /// Passed through to Vision so the YOLO model receives an upright image.
        let exifOrientation: CGImagePropertyOrientation
    }

    private(set) var latestPixelBuffer: CVPixelBuffer?
    private(set) var latestTimestamp: TimeInterval = 0
    private(set) var latestExifOrientation: CGImagePropertyOrientation = .downMirrored
    private var continuations: [UUID: AsyncStream<Frame>.Continuation] = [:]

    /// Replaces any older frame so inference workers always consume the most
    /// recent sample rather than growing an unbounded queue.
    func publish(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        exifOrientation: CGImagePropertyOrientation = .downMirrored
    ) {
        latestPixelBuffer = pixelBuffer
        latestTimestamp = timestamp
        latestExifOrientation = exifOrientation
        let frame = Frame(pixelBuffer: pixelBuffer, timestamp: timestamp, exifOrientation: exifOrientation)
        for continuation in continuations.values {
            continuation.yield(frame)
        }
    }

    func latestFrame() -> Frame? {
        guard let latestPixelBuffer else { return nil }
        return Frame(pixelBuffer: latestPixelBuffer, timestamp: latestTimestamp, exifOrientation: latestExifOrientation)
    }

    func subscribe() -> AsyncStream<Frame> {
        let id = UUID()
        // bufferingNewest(1): if a worker is busy, drop the older frame and keep
        // the latest — inference always runs on the most recent data.
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
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
