import ArgumentParser
import Foundation
import GhostKit

struct SnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Capture, compare, or check UI state for an application."
    )

    @Argument(help: "Application name.")
    var app: String

    @Argument(help: "Action: capture, compare, or check.")
    var action: String

    @Argument(help: "Snapshot label, e.g. 'before-dns-change'.")
    var label: String

    @Option(name: .long, help: "Maximum items in lists. Default: 10.")
    var maxItems: Int = 10

    func run() async throws {
        let blocklist = Blocklist()
        let appResolver = AppResolver()
        let pipeline = PruningPipeline()
        let context = PruningContext(maxItems: maxItems)

        try blocklist.check(appName: app)
        let runningApp = try appResolver.resolve(name: app)

        var reader = AXTreeReader()
        let tree = try reader.readTree(pid: runningApp.processIdentifier)
        let pruned = pipeline.prune(tree, context: context)

        // Use the shared snapshot store (in a real long-running process this persists;
        // for CLI invocations we need to use a file-backed store — for now, capture writes
        // to a temp file and compare/check reads from it)
        let store = FileBackedSnapshotStore()

        switch action {
        case "capture":
            try store.capture(app: app, label: label, tree: pruned)
            print("Snapshot \"\(label)\" captured for \(app).")

        case "compare":
            let diff = try store.compare(app: app, label: label, currentTree: pruned)
            if diff.isEmpty {
                print("No changes since snapshot \"\(label)\".")
            } else {
                print("Changes since snapshot \"\(label)\":")
                for entry in diff {
                    print("  \(entry.description)")
                }
            }

        case "check":
            let matches = try store.check(app: app, label: label, currentTree: pruned)
            if matches {
                print("Current state matches snapshot \"\(label)\".")
            } else {
                print("Current state does NOT match snapshot \"\(label)\".")
                // Also show the diff for context
                let diff = try store.compare(app: app, label: label, currentTree: pruned)
                for entry in diff {
                    print("  \(entry.description)")
                }
            }

        default:
            throw GhostError.invalidAction(action: action, reason: "unknown snapshot action. Valid: capture, compare, check")
        }
    }
}

/// File-backed snapshot store for CLI use (survives across CLI invocations).
private struct FileBackedSnapshotStore {
    private let baseDir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.baseDir = "\(home)/.ghost/snapshots"
        try? FileManager.default.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
    }

    func capture(app: String, label: String, tree: AXNode) throws {
        // Save concise format for text-level comparison
        let concise = ConciseSerializer().serialize(tree)
        let path = filePath(app: app, label: label)
        try concise.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func compare(app: String, label: String, currentTree: AXNode) throws -> [DiffEntry] {
        let path = filePath(app: app, label: label)
        guard let savedData = FileManager.default.contents(atPath: path),
              let savedConcise = String(data: savedData, encoding: .utf8)
        else {
            throw GhostError.elementNotFound(target: "snapshot \"\(label)\" for \(app)")
        }

        let currentConcise = ConciseSerializer().serialize(currentTree)

        if currentConcise == savedConcise {
            return []
        }

        // Produce a line-level diff between saved and current
        let savedLines = Set(savedConcise.components(separatedBy: "\n"))
        let currentLines = Set(currentConcise.components(separatedBy: "\n"))

        var entries: [DiffEntry] = []
        for line in savedLines.subtracting(currentLines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                entries.append(.removed(path: app, detail: trimmed))
            }
        }
        for line in currentLines.subtracting(savedLines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                entries.append(.added(path: app, detail: trimmed))
            }
        }

        if entries.isEmpty {
            // Whitespace-only differences
            entries.append(.changed(path: app, field: "formatting", from: "snapshot", to: "current"))
        }

        return entries
    }

    func check(app: String, label: String, currentTree: AXNode) throws -> Bool {
        let diff = try compare(app: app, label: label, currentTree: currentTree)
        return diff.isEmpty
    }

    private func filePath(app: String, label: String) -> String {
        let safeName = app.lowercased().replacingOccurrences(of: " ", with: "-")
        return "\(baseDir)/\(safeName)--\(label).txt"
    }
}
