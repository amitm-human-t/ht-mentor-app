import OSLog
import Foundation

// MARK: - OSLog channels
// All logs flow through OSLog (visible via Console.app / stream-logs.sh).
// .error and .fault entries are ALSO mirrored to a plain-text file in
// Library/Logs/handx-debug.log so Claude can pull them with pull-logs.sh.

enum AppLogger {
    static let assets    = Logger(subsystem: "humanx.p2-app", category: "assets")
    static let runtime   = Logger(subsystem: "humanx.p2-app", category: "runtime")
    static let inference = Logger(subsystem: "humanx.p2-app", category: "inference")
    static let video     = Logger(subsystem: "humanx.p2-app", category: "debug-video")
    static let device    = Logger(subsystem: "humanx.p2-app", category: "device")

    // MARK: - File sink

    /// Append an error/fault-level message to the on-device debug log file.
    /// Called automatically by the extension helpers below.
    static func writeToFile(level: String, category: String, message: String) {
        DebugLogFile.shared.append(level: level, category: category, message: message)
    }
}

// MARK: - Debug log file writer

/// Writes to <AppContainer>/Library/Logs/handx-debug.log.
/// Capped at ~500 KB — older entries are trimmed automatically.
final class DebugLogFile {
    static let shared = DebugLogFile()

    private let logURL: URL
    private let queue = DispatchQueue(label: "handx.debuglog", qos: .utility)
    private static let maxBytes = 500 * 1024  // 500 KB

    private init() {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logURL = logsDir.appendingPathComponent("handx-debug.log")
    }

    func append(level: String, category: String, message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(level)] [\(category)] \(message)\n"
        queue.async { [weak self] in
            guard let self else { return }
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logURL.path) {
                    if let handle = try? FileHandle(forUpdating: self.logURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logURL, options: .atomic)
                }
                self.trimIfNeeded()
            }
        }
    }

    private func trimIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? Int,
              size > Self.maxBytes,
              let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return }

        // Drop oldest 40% of lines
        let lines = text.components(separatedBy: "\n")
        let keep = lines.dropFirst(lines.count * 2 / 5)
        let trimmed = keep.joined(separator: "\n")
        try? trimmed.data(using: .utf8)?.write(to: logURL, options: .atomic)
    }
}

// MARK: - Convenience wrappers
// Use these instead of bare Logger calls when you want the message mirrored
// to the pull-able log file (warnings, errors, faults).
//
// Example:
//   AppLogger.runtime.fileError("Camera failed: \(error)")
//   AppLogger.inference.fileWarning("Model not loaded for task \(id)")

extension Logger {
    private var categoryName: String {
        // Extract category from the Logger's description
        // Logger doesn't expose category directly — we use a fixed label per call site
        "app"
    }

    /// Log at .warning level AND write to the debug file.
    func fileWarning(_ message: String, category: String = "app") {
        self.warning("\(message, privacy: .public)")
        AppLogger.writeToFile(level: "WARN", category: category, message: message)
    }

    /// Log at .error level AND write to the debug file.
    func fileError(_ message: String, category: String = "app") {
        self.error("\(message, privacy: .public)")
        AppLogger.writeToFile(level: "ERROR", category: category, message: message)
    }

    /// Log at .fault level AND write to the debug file.
    func fileFault(_ message: String, category: String = "app") {
        self.fault("\(message, privacy: .public)")
        AppLogger.writeToFile(level: "FAULT", category: category, message: message)
    }
}
