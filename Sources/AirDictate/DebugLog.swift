import AppKit
import Foundation
import os

final class DebugLog: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published var debugEnabled = false
    @Published var lastErrorMessage = "None"

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        enum Level: String, CaseIterable {
            case info, error, debug
        }
    }

    func info(_ message: String) {
        append(level: .info, message: message)
    }

    func error(_ message: String) {
        append(level: .error, message: message)
    }

    func debug(_ message: String) {
        guard debugEnabled else { return }
        append(level: .debug, message: message)
    }

    private func append(level: LogEntry.Level, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > 500 { self.entries.removeFirst(100) }
            if level == .error { self.lastErrorMessage = message }
        }
        os.Logger().log(level: level == .error ? .error : .info, "\(message)")
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }

    func copyToClipboard() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let text = self.entries.map { "[\($0.timestamp) \($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
