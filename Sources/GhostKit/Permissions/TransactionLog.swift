import Foundation

/// A single logged action with full context.
public struct TransactionEntry: Codable {
    public let timestamp: String
    public let tool: String
    public let action: String
    public let app: String
    public let target: String
    public let result: String
    public let rule: String?

    public init(tool: String, action: String, app: String, target: String, result: String, rule: String?) {
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: Date())
        self.tool = tool
        self.action = action
        self.app = app
        self.target = target
        self.result = result
        self.rule = rule
    }
}

/// Logs all Ghost actions for auditing and debugging.
public final class TransactionLog {
    private var entries: [TransactionEntry] = []
    private let logPath: String?

    public init(logPath: String? = nil) {
        self.logPath = logPath
    }

    public func log(_ entry: TransactionEntry) {
        entries.append(entry)
        writeToFile(entry)
    }

    public func log(
        tool: String,
        action: String,
        app: String,
        target: String,
        result: String,
        rule: String? = nil
    ) {
        let entry = TransactionEntry(
            tool: tool,
            action: action,
            app: app,
            target: target,
            result: result,
            rule: rule
        )
        log(entry)
    }

    public var allEntries: [TransactionEntry] { entries }
    public var count: Int { entries.count }

    private func writeToFile(_ entry: TransactionEntry) {
        guard let path = logPath ?? defaultLogPath() else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry),
              var json = String(data: data, encoding: .utf8)
        else { return }

        json += "\n"

        if FileManager.default.fileExists(atPath: path) {
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            handle.seekToEndOfFile()
            handle.write(json.data(using: .utf8)!)
            handle.closeFile()
        } else {
            // Create directory if needed
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? json.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func defaultLogPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghost/logs/transactions.jsonl"
    }
}
