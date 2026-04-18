import Foundation
import AVFAudio
import OSLog

@MainActor
@Observable
final class AudioService {
    private var effectPlayer: AVAudioPlayer?
    private var calloutPlayer: AVAudioPlayer?
    private var backgroundPlayer: AVAudioPlayer?

    /// Background volume — can be adjusted by the user in settings.
    var backgroundVolume: Float = 0.25 {
        didSet { backgroundPlayer?.volume = backgroundVolume }
    }

    init() {
        configureAudioSession()
    }

    // MARK: - Background music (looping, low volume)

    func startBackground() {
        let tracks: [BundledAsset] = [
            BundledAsset(pathComponents: ["sounds", "backgrounds", "background1"], fileExtension: "mp3", kind: .sound),
            BundledAsset(pathComponents: ["sounds", "backgrounds", "background2"], fileExtension: "mp3", kind: .sound)
        ]
        let asset = tracks.randomElement()!
        guard let url = asset.locate(in: .main) else {
            AppLogger.runtime.debug("AudioService: no background music found, skipping")
            return
        }
        backgroundPlayer = try? AVAudioPlayer(contentsOf: url)
        backgroundPlayer?.numberOfLoops = -1
        backgroundPlayer?.volume = backgroundVolume
        backgroundPlayer?.play()
    }

    func stopBackground() {
        backgroundPlayer?.stop()
        backgroundPlayer = nil
    }

    func pauseBackground() {
        backgroundPlayer?.pause()
    }

    func resumeBackground() {
        backgroundPlayer?.play()
    }

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

    // MARK: - Session setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
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
