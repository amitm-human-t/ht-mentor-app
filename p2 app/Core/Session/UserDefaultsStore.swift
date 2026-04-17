import Foundation

/// Typed access to app-level UserDefaults values.
/// All keys are prefixed with "hx_" to avoid collisions.
enum UserDefaultsStore {
    private static let defaults = UserDefaults.standard

    // MARK: - User selection

    /// Persisted ID of the last active trainee. Restored on app launch.
    static var lastActiveUserID: UUID? {
        get { defaults.string(forKey: "hx_lastActiveUserID").flatMap { UUID(uuidString: $0) } }
        set { defaults.set(newValue?.uuidString, forKey: "hx_lastActiveUserID") }
    }

    // MARK: - Debug

    /// Show inference bounding boxes on the live preview overlay.
    static var debugOverlaysEnabled: Bool {
        get { defaults.bool(forKey: "hx_debugOverlaysEnabled") }
        set { defaults.set(newValue, forKey: "hx_debugOverlaysEnabled") }
    }

    /// CoreML confidence threshold (0.0–1.0). Default 0.20.
    static var confidenceThreshold: Float {
        get {
            let v = defaults.float(forKey: "hx_confidenceThreshold")
            return v == 0 ? 0.20 : v
        }
        set { defaults.set(newValue, forKey: "hx_confidenceThreshold") }
    }

    /// Default input source (rawValue of RunnerCoordinator.InputSource).
    static var defaultInputSource: String? {
        get { defaults.string(forKey: "hx_defaultInputSource") }
        set { defaults.set(newValue, forKey: "hx_defaultInputSource") }
    }
}
