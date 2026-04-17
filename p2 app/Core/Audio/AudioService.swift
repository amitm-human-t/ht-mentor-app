import Foundation
import AVFAudio


@MainActor
@Observable
final class AudioService {
    private var player: AVAudioPlayer?

    func play(_ sound: SoundCatalog) {
        guard let url = sound.asset.locate(in: .main) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

enum SoundCatalog: CaseIterable {
    case success
    case fail

    var asset: BundledAsset {
        switch self {
        case .success:
            return BundledAsset(pathComponents: ["effects", "success"], fileExtension: "wav", kind: .sound)
        case .fail:
            return BundledAsset(pathComponents: ["effects", "fail"], fileExtension: "wav", kind: .sound)
        }
    }
}
