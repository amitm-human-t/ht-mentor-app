@preconcurrency import AVFoundation
import AVKit

import Foundation
import OSLog

/// Replays bundled training videos into the shared frame bus so task logic can
/// run against deterministic footage instead of the live camera.
@MainActor
@Observable
final class DebugVideoFrameSource {
    struct BundledVideo: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let url: URL
        let relatedTasks: Set<TaskIdentifier>
    }

    private(set) var selectedVideoURL: URL?
    private(set) var bundledVideos: [BundledVideo] = []
    private(set) var isRunning = false
    private(set) var previewPlayer: AVPlayer?

    private var playbackTask: Task<Void, Never>?
    private var playerLoopObserver: NSObjectProtocol?

    func refreshBundledVideos(bundle: Bundle = .main) {
        let fileManager = FileManager.default
        let supportedExtensions = Set(["mp4", "mov", "m4v"])
        var discovered: [URL] = []

        if let resourceURL = bundle.resourceURL {
            let debugVideosFolder = resourceURL.appendingPathComponent("DebugVideos", isDirectory: true)
            if let enumerator = fileManager.enumerator(at: debugVideosFolder, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator where supportedExtensions.contains(url.pathExtension.lowercased()) {
                    discovered.append(url)
                }
            }

            if discovered.isEmpty,
               let enumerator = fileManager.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator where supportedExtensions.contains(url.pathExtension.lowercased()) {
                    discovered.append(url)
                }
            }
        }

        bundledVideos = Array(Set(discovered))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                BundledVideo(
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    relatedTasks: Self.matchingTasks(for: url.deletingPathExtension().lastPathComponent)
                )
            }

        AppLogger.video.info("Discovered \(self.bundledVideos.count) bundled debug videos")
        for video in self.bundledVideos {
            AppLogger.video.debug("Bundled debug video: \(video.url.path, privacy: .public)")
        }

        if selectedVideoURL == nil, let first = bundledVideos.first?.url {
            selectVideo(url: first)
        }
    }

    func selectVideo(url: URL) {
        selectedVideoURL = url

        let player: AVPlayer
        if let previewPlayer {
            player = previewPlayer
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        } else {
            let newPlayer = AVPlayer()
            newPlayer.actionAtItemEnd = .pause
            newPlayer.isMuted = true
            previewPlayer = newPlayer
            player = newPlayer
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }

        player.actionAtItemEnd = .pause
        player.isMuted = true
        installLoopObserver(for: player)
        Task {
            _ = await player.seek(to: .zero)
            player.play()
        }

        AppLogger.video.info("Selected debug video: \(url.lastPathComponent, privacy: .public)")
    }

    func preferredVideos(for task: TaskIdentifier?) -> [BundledVideo] {
        guard let task else { return bundledVideos }
        let matched = bundledVideos.filter { $0.relatedTasks.contains(task) }
        return matched.isEmpty ? bundledVideos : matched
    }

    func selectPreferredVideo(for task: TaskIdentifier?) {
        let candidates = preferredVideos(for: task)
        guard let current = selectedVideoURL else {
            if let first = candidates.first?.url {
                selectVideo(url: first)
            }
            return
        }

        if !candidates.contains(where: { $0.url == current }), let first = candidates.first?.url {
            selectVideo(url: first)
        }
    }

    func start(frameBus: CameraFrameBus) async throws {
        guard let selectedVideoURL else {
            throw DebugVideoError.videoNotSelected
        }

        stop()
        isRunning = true
        AppLogger.video.info("Starting debug video playback from \(selectedVideoURL.lastPathComponent, privacy: .public)")

        if previewPlayer == nil {
            selectVideo(url: selectedVideoURL)
        } else {
            previewPlayer?.replaceCurrentItem(with: AVPlayerItem(url: selectedVideoURL))
            if let previewPlayer {
                installLoopObserver(for: previewPlayer)
            }
        }

        if let previewPlayer {
            _ = await previewPlayer.seek(to: .zero)
            previewPlayer.play()
        }

        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Self.streamFrames(from: selectedVideoURL, into: frameBus)
                } catch is CancellationError {
                    AppLogger.video.debug("Cancelled debug video stream for \(selectedVideoURL.lastPathComponent, privacy: .public)")
                    break
                } catch {
                    AppLogger.video.error("Debug video streaming failed: \(error.localizedDescription, privacy: .public)")
                    break
                }
            }

            await MainActor.run {
                self?.isRunning = false
            }
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        previewPlayer?.pause()
        removeLoopObserver()
        isRunning = false
    }

    private func installLoopObserver(for player: AVPlayer) {
        removeLoopObserver()
        player.actionAtItemEnd = .none
        playerLoopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            Task {
                _ = await player.seek(to: .zero)
                player.play()
            }
        }
    }

    private func removeLoopObserver() {
        if let playerLoopObserver {
            NotificationCenter.default.removeObserver(playerLoopObserver)
            self.playerLoopObserver = nil
        }
    }

    private static func streamFrames(from url: URL, into frameBus: CameraFrameBus) async throws {
        let asset = AVURLAsset(url: url)
        let track = try await loadVideoTrack(from: asset)
        let readerContext = try makeReader(asset: asset, track: track)
        var previousTimestamp: Double?
        var frameCount = 0

        while readerContext.reader.status == .reading,
              let sampleBuffer = readerContext.output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if let previousTimestamp {
                let delta = max(0.001, timestamp - previousTimestamp)
                try await Task.sleep(for: .seconds(delta))
            }

            previousTimestamp = timestamp
            frameCount += 1
            await frameBus.publish(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }

        if readerContext.reader.status == .failed {
            throw readerContext.reader.error ?? DebugVideoError.readerConfigurationFailed
        }

        guard frameCount > 0 else {
            throw DebugVideoError.noFramesDecoded
        }

        AppLogger.video.info("Streamed \(frameCount) video frames from \(url.lastPathComponent, privacy: .public)")
    }

    private static func loadVideoTrack(from asset: AVAsset) async throws -> AVAssetTrack {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DebugVideoError.videoTrackMissing
        }
        return track
    }

    private static func makeReader(asset: AVAsset, track: AVAssetTrack) throws -> ReaderContext {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw DebugVideoError.readerConfigurationFailed
        }

        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? DebugVideoError.readerConfigurationFailed
        }

        return ReaderContext(reader: reader, output: output)
    }

    private static func matchingTasks(for fileStem: String) -> Set<TaskIdentifier> {
        let normalizedName = normalizeToken(fileStem)
        return Set(TaskIdentifier.allCases.filter { task in
            task.embeddedVideoKeywords.contains { keyword in
                normalizedName.contains(normalizeToken(keyword))
            }
        })
    }

    private static func normalizeToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private struct ReaderContext {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
    }
}

enum DebugVideoError: LocalizedError {
    case videoNotSelected
    case videoTrackMissing
    case readerConfigurationFailed
    case noFramesDecoded

    var errorDescription: String? {
        switch self {
        case .videoNotSelected:
            return "Select a debug video before starting video-backed inference."
        case .videoTrackMissing:
            return "The selected file does not contain a readable video track."
        case .readerConfigurationFailed:
            return "The debug video reader could not be configured."
        case .noFramesDecoded:
            return "No frames could be decoded from the selected debug video."
        }
    }
}
