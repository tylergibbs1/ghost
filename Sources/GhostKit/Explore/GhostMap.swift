import Foundation

/// Serializes and deserializes AppGraph to/from the .ghostmap JSON format.
public struct GhostMap {
    public init() {}

    // MARK: - Save

    /// Serialize an AppGraph to JSON and save to disk.
    public func save(_ graph: AppGraph, to path: String) throws {
        let dict = serialize(graph)
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Default path for an app's ghostmap.
    public static func defaultPath(for appName: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let safeName = appName.lowercased().replacingOccurrences(of: " ", with: "-")
        return "\(home)/.ghost/maps/\(safeName).ghostmap"
    }

    // MARK: - Load

    /// Load an AppGraph from a .ghostmap file.
    public func load(from path: String) throws -> AppGraph {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw GhostError.elementNotFound(target: "ghostmap at \(path)")
        }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GhostError.invalidPath(raw: path)
        }
        return try deserialize(dict)
    }

    // MARK: - Serialize

    private func serialize(_ graph: AppGraph) -> [String: Any] {
        let formatter = ISO8601DateFormatter()

        var statesDict: [String: Any] = [:]
        for (id, state) in graph.states {
            var stateDict: [String: Any] = [
                "label": state.label,
                "depth": state.depth,
                "visitCount": state.visitCount,
                "actions": state.actions.map { serializeAction($0) },
                "transitions": state.transitions,
            ]
            if let snapshot = state.treeSnapshot {
                stateDict["tree"] = snapshot
            }
            statesDict[id] = stateDict
        }

        return [
            "format": "ghostmap",
            "version": 1,
            "app": graph.appName,
            "exploredAt": formatter.string(from: graph.exploredAt),
            "osVersion": graph.osVersion,
            "appVersion": graph.appVersion as Any,
            "rootState": graph.rootStateId,
            "states": statesDict,
            "stats": [
                "statesDiscovered": graph.stats.statesDiscovered,
                "actionsDiscovered": graph.stats.actionsDiscovered,
                "actionsExplored": graph.stats.actionsExplored,
                "transitionsRecorded": graph.stats.transitionsRecorded,
                "duration": graph.stats.duration,
                "maxDepth": graph.stats.maxDepth,
            ],
        ]
    }

    private func serializeAction(_ action: DiscoveredAction) -> [String: Any] {
        var dict: [String: Any] = [
            "id": action.id,
            "action": action.action,
            "role": action.role,
            "path": action.path,
            "explored": action.explored,
        ]
        if let name = action.name { dict["name"] = name }
        if let effect = action.effect { dict["effect"] = effect.rawValue }
        if let paramType = action.paramType { dict["paramType"] = paramType }
        return dict
    }

    // MARK: - Deserialize

    private func deserialize(_ dict: [String: Any]) throws -> AppGraph {
        guard let appName = dict["app"] as? String,
              let rootStateId = dict["rootState"] as? String,
              let statesDict = dict["states"] as? [String: [String: Any]]
        else {
            throw GhostError.invalidPath(raw: "invalid ghostmap format")
        }

        let graph = AppGraph(appName: appName, rootStateId: rootStateId)
        graph.appVersion = dict["appVersion"] as? String

        for (id, stateDict) in statesDict {
            guard let label = stateDict["label"] as? String,
                  let depth = stateDict["depth"] as? Int
            else { continue }

            let state = AppState(id: id, label: label, fingerprint: id, depth: depth)
            state.visitCount = stateDict["visitCount"] as? Int ?? 1
            state.treeSnapshot = stateDict["tree"] as? String
            state.transitions = stateDict["transitions"] as? [String: String] ?? [:]

            if let actionsArr = stateDict["actions"] as? [[String: Any]] {
                state.actions = actionsArr.compactMap { deserializeAction($0) }
            }

            graph.states[id] = state
        }

        if let statsDict = dict["stats"] as? [String: Any] {
            graph.stats.statesDiscovered = statsDict["statesDiscovered"] as? Int ?? 0
            graph.stats.actionsDiscovered = statsDict["actionsDiscovered"] as? Int ?? 0
            graph.stats.actionsExplored = statsDict["actionsExplored"] as? Int ?? 0
            graph.stats.transitionsRecorded = statsDict["transitionsRecorded"] as? Int ?? 0
            graph.stats.duration = statsDict["duration"] as? TimeInterval ?? 0
            graph.stats.maxDepth = statsDict["maxDepth"] as? Int ?? 0
        }

        return graph
    }

    private func deserializeAction(_ dict: [String: Any]) -> DiscoveredAction? {
        guard let id = dict["id"] as? String,
              let action = dict["action"] as? String,
              let role = dict["role"] as? String,
              let path = dict["path"] as? String
        else { return nil }

        var da = DiscoveredAction(id: id, action: action, role: role, name: dict["name"] as? String, path: path)
        da.explored = dict["explored"] as? Bool ?? false
        if let effectStr = dict["effect"] as? String {
            da.effect = ActionEffect(rawValue: effectStr)
        }
        da.paramType = dict["paramType"] as? String
        return da
    }

    // MARK: - Human-readable summary

    /// Print a human-readable summary of a ghostmap.
    public func summary(_ graph: AppGraph) -> String {
        var lines: [String] = []

        lines.append("App: \(graph.appName)")
        lines.append("States: \(graph.stats.statesDiscovered)")
        lines.append("Actions: \(graph.stats.actionsDiscovered) (\(graph.stats.actionsExplored) explored)")
        lines.append("Transitions: \(graph.stats.transitionsRecorded)")
        lines.append("Max depth: \(graph.stats.maxDepth)")
        lines.append("Duration: \(String(format: "%.1f", graph.stats.duration))s")
        lines.append("")

        // State tree (BFS from root)
        lines.append("State graph:")
        var visited = Set<String>()
        var queue: [(String, Int)] = [(graph.rootStateId, 0)]

        while !queue.isEmpty {
            let (stateId, depth) = queue.removeFirst()
            guard !visited.contains(stateId) else { continue }
            visited.insert(stateId)

            guard let state = graph.states[stateId] else { continue }
            let indent = String(repeating: "  ", count: depth)
            let actionCount = state.actions.count
            let toggles = state.actions.filter { $0.effect == .valueToggle }.count
            let nav = state.actions.filter { $0.effect == .stateChange }.count

            lines.append("\(indent)[\(state.label)]  (\(actionCount) actions, \(nav) nav, \(toggles) toggles)")

            // Show key actions
            for action in state.actions.prefix(8) {
                if action.effect == .stateChange || action.effect == .valueToggle {
                    let effectStr = action.effect?.rawValue ?? "?"
                    let name = action.name ?? action.role
                    lines.append("\(indent)  \(action.action) \"\(name)\" → \(effectStr)")
                }
            }
            if state.actions.count > 8 {
                let remaining = state.actions.count - 8
                lines.append("\(indent)  ... and \(remaining) more actions")
            }

            for (_, targetId) in state.transitions.sorted(by: { $0.key < $1.key }) {
                queue.append((targetId, depth + 1))
            }
        }

        return lines.joined(separator: "\n")
    }
}
