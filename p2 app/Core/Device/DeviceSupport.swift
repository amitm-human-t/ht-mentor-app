import Foundation
import OSLog

struct DeviceSupportSnapshot: Equatable {
    enum Level: Equatable {
        case supported
        case warning
    }

    let level: Level
    let title: String
    let message: String
    let hardwareIdentifier: String

    static func current() -> DeviceSupportSnapshot {
        #if targetEnvironment(simulator)
        return DeviceSupportSnapshot(
            level: .warning,
            title: "Simulator build",
            message: "Task behavior and camera performance still need validation on an M-series iPad Pro.",
            hardwareIdentifier: "simulator"
        )
        #else
        let identifier = hardwareIdentifier()
        let supportedPrefixes = ["iPad13", "iPad14", "iPad16"]
        if supportedPrefixes.contains(where: identifier.hasPrefix) {
            AppLogger.device.info("Supported hardware detected: \(identifier, privacy: .public)")
            return DeviceSupportSnapshot(
                level: .supported,
                title: "Supported hardware",
                message: "This device matches the current v1 support matrix.",
                hardwareIdentifier: identifier
            )
        }
        AppLogger.device.notice("Unsupported hardware warning for identifier: \(identifier, privacy: .public)")
        return DeviceSupportSnapshot(
            level: .warning,
            title: "Unsupported hardware warning",
            message: "v1 is tuned for 2021 M1, 2022 M2, and 2024 M4 iPad Pro hardware. You can continue, but runtime parity is not guaranteed.",
            hardwareIdentifier: identifier
        )
        #endif
    }

    private static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
