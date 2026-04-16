import Foundation
import OSLog

struct StartupDiagnostics: Sendable {
    struct Entry: Identifiable, Hashable, Sendable {
        let id = UUID()
        let asset: BundledAsset
        let found: Bool
        let location: String?
    }

    var entries: [Entry] = []

    var missingEntries: [Entry] {
        entries.filter { !$0.found }
    }

    var isHealthy: Bool {
        missingEntries.isEmpty
    }

    static func run(bundle: Bundle, assetCatalog: AssetCatalog) async -> StartupDiagnostics {
        let assets = assetCatalog.models + assetCatalog.sounds
        let entries = assets.map { asset in
            let location = asset.locate(in: bundle)?.lastPathComponent
            if let location {
                AppLogger.assets.info("Startup asset check passed for \(asset.displayName, privacy: .public) at \(location, privacy: .public)")
            } else {
                AppLogger.assets.error("Startup asset check failed for \(asset.displayName, privacy: .public)")
            }
            return Entry(asset: asset, found: location != nil, location: location)
        }
        return StartupDiagnostics(entries: entries)
    }
}
