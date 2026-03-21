import Foundation

/// In-memory store for accessibility tree snapshots.
/// Snapshots are scoped per-app and identified by label.
public final class SnapshotStore {
    /// Key: "appName:label"
    private var snapshots: [String: AXNode] = [:]

    public init() {}

    // MARK: - Capture

    /// Save the current tree state for an app with a label.
    public func capture(app: String, label: String, tree: AXNode) {
        let key = Self.key(app: app, label: label)
        // Deep copy so the snapshot isn't affected by future mutations
        var counter = 0
        snapshots[key] = tree.deepCopy(idCounter: &counter)
    }

    // MARK: - Compare

    /// Diff the current tree against a saved snapshot.
    /// Returns the diff entries showing what changed since the snapshot was taken.
    public func compare(app: String, label: String, currentTree: AXNode) throws -> [DiffEntry] {
        let key = Self.key(app: app, label: label)
        guard let snapshot = snapshots[key] else {
            throw GhostError.elementNotFound(target: "snapshot \"\(label)\" for \(app)")
        }

        let differ = TreeDiffer()
        return differ.diff(before: snapshot, after: currentTree)
    }

    // MARK: - Check

    /// Check if the current tree matches a saved snapshot (no diff = match).
    public func check(app: String, label: String, currentTree: AXNode) throws -> Bool {
        let diff = try compare(app: app, label: label, currentTree: currentTree)
        return diff.isEmpty
    }

    // MARK: - Management

    /// Check if a snapshot exists.
    public func exists(app: String, label: String) -> Bool {
        snapshots[Self.key(app: app, label: label)] != nil
    }

    /// Remove a snapshot.
    public func remove(app: String, label: String) {
        snapshots.removeValue(forKey: Self.key(app: app, label: label))
    }

    /// List all snapshot labels for an app.
    public func labels(for app: String) -> [String] {
        let prefix = app.lowercased() + ":"
        return snapshots.keys
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .sorted()
    }

    /// Remove all snapshots.
    public func clear() {
        snapshots.removeAll()
    }

    private static func key(app: String, label: String) -> String {
        "\(app.lowercased()):\(label)"
    }
}
