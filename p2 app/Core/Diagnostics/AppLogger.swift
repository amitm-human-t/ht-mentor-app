import OSLog

enum AppLogger {
    static let assets = Logger(subsystem: "humanx.p2-app", category: "assets")
    static let runtime = Logger(subsystem: "humanx.p2-app", category: "runtime")
    static let inference = Logger(subsystem: "humanx.p2-app", category: "inference")
    static let video = Logger(subsystem: "humanx.p2-app", category: "debug-video")
    static let device = Logger(subsystem: "humanx.p2-app", category: "device")
}
