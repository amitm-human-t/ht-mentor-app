import Foundation
import AVFAudio
import OSLog

@MainActor
@Observable
final class AudioService {
    private var effectPlayer: AVAudioPlayer?
    private var calloutPlayer: AVAudioPlayer?

    // MARK: - Effect sounds (success, fail, finished…)

    func play(_ sound: SoundCatalog) {
        guard let url = sound.asset.locate(in: .main) else { return }
        effectPlayer = try? AVAudioPlayer(contentsOf: url)
        effectPlayer?.play()
    }

    // MARK: - Dynamic callout sounds
    // Triggered by task engines via audio_callout RunEvent.
    // dir  = subdirectory under sounds/ (e.g. "tip_positioning", "keylock")
    // file = filename without extension (e.g. "l3", "r7", "1", "13")

    func playCallout(dir: String, file: String) {
        let asset = BundledAsset(
            pathComponents: ["sounds", dir, file],
            fileExtension: "mp3",
            kind: .sound
        )
        guard let url = asset.locate(in: .main) else {
            AppLogger.runtime.warning("AudioService: missing callout sounds/\(dir)/\(file).mp3")
            return
        }
        calloutPlayer = try? AVAudioPlayer(contentsOf: url)
        calloutPlayer?.play()
    }
}

// MARK: - Sound Catalog

enum SoundCatalog: CaseIterable {
    case success
    case success2
    case fail
    case finished
    case gameover

    var asset: BundledAsset {
        switch self {
        case .success:
            return BundledAsset(pathComponents: ["sounds", "effects", "success"],  fileExtension: "wav", kind: .sound)
        case .success2:
            return BundledAsset(pathComponents: ["sounds", "effects", "success2"], fileExtension: "wav", kind: .sound)
        case .fail:
            return BundledAsset(pathComponents: ["sounds", "effects", "fail"],     fileExtension: "wav", kind: .sound)
        case .finished:
            return BundledAsset(pathComponents: ["sounds", "effects", "finished"], fileExtension: "wav", kind: .sound)
        case .gameover:
            return BundledAsset(pathComponents: ["sounds", "effects", "gameover"], fileExtension: "wav", kind: .sound)
        }
    }
}
