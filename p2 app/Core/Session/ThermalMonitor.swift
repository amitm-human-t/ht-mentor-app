import Foundation
import OSLog

/// Observes device thermal state and signals RunnerCoordinator to throttle
/// or pause inference when the Neural Engine is under thermal pressure.
@Observable
@MainActor
final class ThermalMonitor {
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        thermalState = ProcessInfo.processInfo.thermalState
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newState = ProcessInfo.processInfo.thermalState
                self.thermalState = newState
                AppLogger.runtime.fileWarning(
                    "Thermal state changed: \(newState.displayName)",
                    category: "perf"
                )
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Skip every other inference tick — active when state is .serious.
    var shouldThrottle: Bool { thermalState == .serious }

    /// Skip all inference — active when state is .critical.
    var shouldPauseInference: Bool { thermalState == .critical }

    var displayName: String { thermalState.displayName }
}

extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
