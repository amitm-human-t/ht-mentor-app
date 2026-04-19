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

    /// NMS IoU threshold (0.0–1.0). Default 0.45.
    static var iouThreshold: Float {
        get {
            let v = defaults.float(forKey: "hx_iouThreshold")
            return v == 0 ? 0.45 : v
        }
        set { defaults.set(newValue, forKey: "hx_iouThreshold") }
    }

    /// KeyLockV2 overlap gate ("red %") as a fraction 0.0–1.0. Default 0.18.
    static var keyLockSlotOverlapThreshold: Float {
        get {
            let v = defaults.float(forKey: "hx_keylock_overlapThreshold")
            return v == 0 ? 0.18 : v
        }
        set { defaults.set(newValue, forKey: "hx_keylock_overlapThreshold") }
    }

    /// KeyLockV2 hold duration in seconds. Default 1.0s.
    static var keyLockHoldDurationSeconds: Float {
        get {
            let v = defaults.float(forKey: "hx_keylock_holdSeconds")
            return v == 0 ? 1.0 : v
        }
        set { defaults.set(newValue, forKey: "hx_keylock_holdSeconds") }
    }

    /// KeyLockV2 confidence gate (0.0–1.0). Default 0.75.
    static var keyLockAcceptanceConfidence: Float {
        get {
            let v = defaults.float(forKey: "hx_keylock_acceptanceConfidence")
            return v == 0 ? 0.75 : v
        }
        set { defaults.set(newValue, forKey: "hx_keylock_acceptanceConfidence") }
    }

    /// Slot-ordering orientation switch for debugging coordinate transforms.
    /// false => sort top-to-bottom (default), true => bottom-to-top.
    static var keyLockInvertYOrdering: Bool {
        get { defaults.bool(forKey: "hx_keylock_invertYOrdering") }
        set { defaults.set(newValue, forKey: "hx_keylock_invertYOrdering") }
    }

    /// Default input source (rawValue of RunnerCoordinator.InputSource).
    static var defaultInputSource: String? {
        get { defaults.string(forKey: "hx_defaultInputSource") }
        set { defaults.set(newValue, forKey: "hx_defaultInputSource") }
    }
}
