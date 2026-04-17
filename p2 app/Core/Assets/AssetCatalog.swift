import Foundation
import OSLog

struct AssetCatalog: Sendable {
    let models: [BundledAsset]
    let sounds: [BundledAsset]

    static let production = AssetCatalog(
        models: [
            .init(pathComponents: ["models", "instrument"], fileExtension: "mlpackage", kind: .model),
            .init(pathComponents: ["models", "keylock"], fileExtension: "mlpackage", kind: .model),
            .init(pathComponents: ["models", "rubberband"], fileExtension: "mlpackage", kind: .model),
            .init(pathComponents: ["models", "springs"], fileExtension: "mlpackage", kind: .model),
            .init(pathComponents: ["models", "tippos"], fileExtension: "mlpackage", kind: .model)
        ],
        sounds: [
            // Backgrounds
            .init(pathComponents: ["sounds", "backgrounds", "background1"], fileExtension: "wav", kind: .sound),
            .init(pathComponents: ["sounds", "backgrounds", "background2"], fileExtension: "wav", kind: .sound),
            // Effects
            .init(pathComponents: ["sounds", "effects", "fail"], fileExtension: "wav", kind: .sound),
            .init(pathComponents: ["sounds", "effects", "finished"], fileExtension: "wav", kind: .sound),
            .init(pathComponents: ["sounds", "effects", "gameover"], fileExtension: "wav", kind: .sound),
            .init(pathComponents: ["sounds", "effects", "success"], fileExtension: "wav", kind: .sound),
            .init(pathComponents: ["sounds", "effects", "success2"], fileExtension: "wav", kind: .sound),
            // KeyLock callouts (1–13)
            .init(pathComponents: ["sounds", "keylock", "1"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "2"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "3"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "4"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "5"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "6"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "7"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "8"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "9"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "10"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "11"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "12"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "keylock", "13"], fileExtension: "mp3", kind: .sound),
            // TipPositioning callouts — left hand (l1–l7)
            .init(pathComponents: ["sounds", "tip_positioning", "l1"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "l2"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "l3"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "l4"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "l5"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "l6"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "l7"], fileExtension: "mp3", kind: .sound),
            // TipPositioning callouts — right hand (r1–r7)
            .init(pathComponents: ["sounds", "tip_positioning", "r1"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "r2"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "r3"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "r4"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "r5"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "r6"], fileExtension: "mp3", kind: .sound),
            .init(pathComponents: ["sounds", "tip_positioning", "r7"], fileExtension: "mp3", kind: .sound)
        ]
    )
}

struct BundledAsset: Hashable, Sendable {
    enum Kind: String, Sendable {
        case model
        case sound
    }

    let pathComponents: [String]
    let fileExtension: String
    let kind: Kind

    nonisolated init(name: String, fileExtension: String, kind: Kind) {
        self.pathComponents = [name]
        self.fileExtension = fileExtension
        self.kind = kind
    }

    nonisolated init(pathComponents: [String], fileExtension: String, kind: Kind) {
        self.pathComponents = pathComponents
        self.fileExtension = fileExtension
        self.kind = kind
    }

    nonisolated var displayName: String {
        ([kind.rawValue.capitalized] + pathComponents).joined(separator: "/") + ".\(fileExtension)"
    }

    nonisolated func locate(in bundle: Bundle) -> URL? {
        guard let resourceName = pathComponents.last else { return nil }
        let subdirectory = pathComponents.dropLast().joined(separator: "/")
        let directory = subdirectory.isEmpty ? nil : subdirectory
        if let direct = bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: directory) {
            AppLogger.assets.debug("Found asset via direct lookup: \(direct.path, privacy: .public)")
            return direct
        }
        if kind == .model,
           let compiled = bundle.url(forResource: resourceName, withExtension: "mlmodelc", subdirectory: directory) {
            AppLogger.assets.debug("Found compiled model via direct lookup: \(compiled.path, privacy: .public)")
            return compiled
        }

        guard let resourceURL = bundle.resourceURL else { return nil }
        let allowedExtensions = kind == .model
            ? [fileExtension.lowercased(), "mlmodelc"]
            : [fileExtension.lowercased()]

        if let enumerator = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                let matchesName = url.deletingPathExtension().lastPathComponent == resourceName
                let matchesExtension = allowedExtensions.contains(url.pathExtension.lowercased())
                if matchesName && matchesExtension {
                    AppLogger.assets.debug("Found asset via recursive scan: \(url.path, privacy: .public)")
                    return url
                }
            }
        }

        AppLogger.assets.error("Missing bundled asset: \(self.displayName, privacy: .public)")
        return nil
    }
}
