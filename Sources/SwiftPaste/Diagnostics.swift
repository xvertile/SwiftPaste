import Foundation

/// Opt-in file logging for tracking down input problems that only reproduce with a real
/// mouse and keyboard. Off unless you turn it on:
///
///     defaults write io.bytezero.SwiftPaste debugLogging -bool YES
///
/// Output lands in ~/Library/Logs/SwiftPaste-debug.log
enum Diagnostics {
    static let isEnabled = UserDefaults.standard.bool(forKey: "debugLogging")

    private static let fileURL: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("SwiftPaste-debug.log")
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message())\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
