import AppKit
import ApplicationServices
import Foundation

/// Configuration for an exploration run.
public struct ExploreConfig {
    /// Maximum depth to explore from root state.
    public var maxDepth: Int

    /// Maximum total states to discover before stopping.
    public var maxStates: Int

    /// Maximum time to spend exploring (seconds).
    public var maxDuration: TimeInterval

    /// Milliseconds to wait after each action for UI to settle.
    public var settleTime: UInt64

    /// Whether to explore destructive-looking actions (Delete, Reset, Remove, etc.).
    public var exploreDangerous: Bool

    /// Whether to type test values into text fields.
    public var exploreTextFields: Bool

    /// Progress callback: called after each action with (stats, currentStateLabel).
    public var onProgress: ((ExploreStats, String) -> Void)?

    public init(
        maxDepth: Int = 6,
        maxStates: Int = 200,
        maxDuration: TimeInterval = 300,
        settleTime: UInt64 = 80_000_000,
        exploreDangerous: Bool = false,
        exploreTextFields: Bool = false,
        onProgress: ((ExploreStats, String) -> Void)? = nil
    ) {
        self.maxDepth = maxDepth
        self.maxStates = maxStates
        self.maxDuration = maxDuration
        self.settleTime = settleTime
        self.exploreDangerous = exploreDangerous
        self.exploreTextFields = exploreTextFields
        self.onProgress = onProgress
    }
}

/// Autonomously explores a macOS app by systematically trying every
/// action in every reachable state, building a complete state graph.
public struct ExploreEngine {
    private let fingerprinter = StateFingerprint()
    private let pipeline = PruningPipeline()
    private let resolver = ElementResolver()

    public init() {}

    // MARK: - Main entry point

    /// Explore an app and return its state graph.
    public func explore(pid: pid_t, appName: String, config: ExploreConfig = ExploreConfig()) async throws -> AppGraph {
        let startTime = Date()

        // Read initial state
        let initialTree = try readTree(pid: pid)
        let initialFP = fingerprinter.fingerprint(initialTree)
        let initialLabel = fingerprinter.label(initialTree)

        let graph = AppGraph(appName: appName, rootStateId: initialFP)

        // Create root state
        let rootState = AppState(id: initialFP, label: initialLabel, fingerprint: initialFP, depth: 0)
        rootState.treeSnapshot = ConciseSerializer().serialize(initialTree)
        rootState.actions = discoverActions(in: initialTree)
        graph.states[initialFP] = rootState
        graph.stats.statesDiscovered = 1
        graph.stats.actionsDiscovered = rootState.actions.count

        // BFS exploration queue: (stateId, depth)
        var queue: [(String, Int)] = [(initialFP, 0)]
        var explored = Set<String>()

        while !queue.isEmpty {
            // Check limits
            if graph.stats.statesDiscovered >= config.maxStates { break }
            if Date().timeIntervalSince(startTime) >= config.maxDuration { break }

            let (currentStateId, currentDepth) = queue.removeFirst()
            if explored.contains(currentStateId) { continue }
            if currentDepth >= config.maxDepth { continue }
            explored.insert(currentStateId)

            guard let currentState = graph.states[currentStateId] else { continue }

            // Navigate back to this state if we're not already there
            let currentTree = try readTree(pid: pid)
            let currentFP = fingerprinter.fingerprint(currentTree)

            if currentFP != currentStateId {
                // Try to navigate back to root first, then follow the path
                if let path = graph.findPath(to: { $0.id == currentStateId }) {
                    // Navigate to root by pressing Back or using keyboard shortcut
                    try await navigateToRoot(pid: pid, graph: graph, config: config)
                    // Follow the path
                    for step in path {
                        try await executeAction(step.action, pid: pid, config: config)
                    }
                } else {
                    // Can't reach this state, skip it
                    continue
                }
            }

            // Try each unexplored action in this state
            for i in 0..<currentState.actions.count {
                if currentState.actions[i].explored { continue }
                if Date().timeIntervalSince(startTime) >= config.maxDuration { break }

                let action = currentState.actions[i]

                // Skip dangerous actions unless configured
                if !config.exploreDangerous && isDangerous(action) {
                    currentState.actions[i].explored = true
                    currentState.actions[i].effect = .error
                    continue
                }

                // Skip text fields unless configured
                if !config.exploreTextFields && action.role == "textfield" {
                    currentState.actions[i].explored = true
                    currentState.actions[i].effect = .textInput
                    currentState.actions[i].paramType = "text"
                    continue
                }

                // Execute the action
                let beforeTree = try readTree(pid: pid)

                do {
                    try await executeAction(action, pid: pid, config: config)
                } catch {
                    currentState.actions[i].explored = true
                    currentState.actions[i].effect = .error
                    graph.stats.actionsExplored += 1
                    continue
                }

                // Read the result
                let afterTree = try readTree(pid: pid)
                let afterFP = fingerprinter.fingerprint(afterTree)

                currentState.actions[i].explored = true
                graph.stats.actionsExplored += 1

                if afterFP == currentStateId {
                    // Same state — might be a value toggle or no-op
                    let beforeValue = findValue(action, in: beforeTree)
                    let afterValue = findValue(action, in: afterTree)
                    if beforeValue != afterValue {
                        currentState.actions[i].effect = .valueToggle
                    } else {
                        currentState.actions[i].effect = .noChange
                    }
                } else {
                    // New state discovered
                    currentState.actions[i].effect = .stateChange
                    currentState.transitions[action.id] = afterFP
                    graph.stats.transitionsRecorded += 1

                    if graph.states[afterFP] == nil {
                        // Never-before-seen state
                        let newLabel = fingerprinter.label(afterTree)
                        let newState = AppState(id: afterFP, label: newLabel, fingerprint: afterFP, depth: currentDepth + 1)
                        newState.treeSnapshot = ConciseSerializer().serialize(afterTree)
                        newState.actions = discoverActions(in: afterTree)

                        graph.states[afterFP] = newState
                        graph.stats.statesDiscovered += 1
                        graph.stats.actionsDiscovered += newState.actions.count
                        graph.stats.maxDepth = max(graph.stats.maxDepth, currentDepth + 1)

                        queue.append((afterFP, currentDepth + 1))

                        // Detect dialogs/sheets
                        if hasNewDialog(before: beforeTree, after: afterTree) {
                            currentState.actions[i].effect = .dialogOpened
                        }
                    } else {
                        graph.states[afterFP]!.visitCount += 1
                    }

                    // Navigate back to current state for next action
                    try await navigateBack(pid: pid, config: config)
                }

                config.onProgress?(graph.stats, currentState.label)
            }
        }

        graph.stats.duration = Date().timeIntervalSince(startTime)
        return graph
    }

    // MARK: - Action Discovery

    /// Find all actionable elements in a pruned tree.
    private func discoverActions(in tree: AXNode) -> [DiscoveredAction] {
        var actions: [DiscoveredAction] = []
        var counter = 0
        collectActions(tree, path: "", actions: &actions, counter: &counter)
        return actions
    }

    private func collectActions(
        _ node: AXNode,
        path: String,
        actions: inout [DiscoveredAction],
        counter: inout Int
    ) {
        let currentPath = path.isEmpty ? node.pathSegment : "\(path) > \(node.pathSegment)"

        // Is this node interactive?
        let interactiveRoles: Set<String> = [
            "button", "toggle", "textfield", "dropdown", "combobox",
            "search", "link", "menuItem", "radio", "disclosure",
            "tab", "slider", "item",
        ]

        if interactiveRoles.contains(node.role) || !node.actions.isEmpty {
            let actionType = primaryAction(for: node)
            let action = DiscoveredAction(
                id: "a\(counter)",
                action: actionType,
                role: node.role,
                name: node.name,
                path: currentPath
            )
            actions.append(action)
            counter += 1
        }

        for child in node.children {
            collectActions(child, path: currentPath, actions: &actions, counter: &counter)
        }
    }

    private func primaryAction(for node: AXNode) -> String {
        switch node.role {
        case "textfield", "search", "combobox": return "type"
        case "dropdown": return "select"
        case "slider": return "increment"
        default: return "press"
        }
    }

    // MARK: - Action Execution

    private func executeAction(_ action: DiscoveredAction, pid: pid_t, config: ExploreConfig) async throws {
        let tree = try readTree(pid: pid)

        // Resolve the target element
        let targetNode = try resolver.resolve(target: action.path, in: tree)

        guard let element = targetNode.elementRef else {
            throw GhostError.actionFailed(action: action.action, target: action.path, reason: "no element reference")
        }

        switch action.action {
        case "press":
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        case "select":
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        case "type":
            // Don't actually type — just focus and record it as a text input param
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        default:
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        }

        // Wait for UI to settle
        try await Task.sleep(nanoseconds: config.settleTime)
    }

    // MARK: - Navigation

    /// Try to navigate back to the previous state (undo the last action).
    private func navigateBack(pid: pid_t, config: ExploreConfig) async throws {
        // Strategy: press Escape, then check if we're back
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
        {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        try await Task.sleep(nanoseconds: config.settleTime)

        // If Escape didn't work, try Cmd+[ (Back) for navigation apps
        let tree = try readTree(pid: pid)
        // Look for a Back button
        func findBack(_ node: AXNode) -> AXNode? {
            if let name = node.name, name.lowercased().contains("back") { return node }
            if let id = node.axIdentifier, id.lowercased().contains("back") { return node }
            return node.children.compactMap { findBack($0) }.first
        }
        if let backButton = findBack(tree), let element = backButton.elementRef {
            AXUIElementPerformAction(element, kAXPressAction as CFString)
            try await Task.sleep(nanoseconds: config.settleTime)
        }
    }

    /// Navigate to the root state from anywhere.
    private func navigateToRoot(pid: pid_t, graph: AppGraph, config: ExploreConfig) async throws {
        // Press Escape repeatedly to dismiss dialogs/sheets
        for _ in 0..<5 {
            let tree = try readTree(pid: pid)
            let fp = fingerprinter.fingerprint(tree)
            if fp == graph.rootStateId { return }

            let source = CGEventSource(stateID: .hidSystemState)
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
            {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            try await Task.sleep(nanoseconds: config.settleTime)
        }

        // If still not at root, try Cmd+, (Settings/Preferences as a known root)
        // or just accept wherever we are
    }

    // MARK: - State Analysis

    private func findValue(_ action: DiscoveredAction, in tree: AXNode) -> String? {
        guard let node = try? resolver.resolve(target: action.path, in: tree) else { return nil }
        return node.value
    }

    private func hasNewDialog(before: AXNode, after: AXNode) -> Bool {
        let beforeDialogs = countByRole(before, roles: ["dialog", "sheet"])
        let afterDialogs = countByRole(after, roles: ["dialog", "sheet"])
        return afterDialogs > beforeDialogs
    }

    private func countByRole(_ node: AXNode, roles: Set<String>) -> Int {
        var count = roles.contains(node.role) ? 1 : 0
        for child in node.children {
            count += countByRole(child, roles: roles)
        }
        return count
    }

    // MARK: - Safety

    private static let dangerousPatterns: [String] = [
        "delete", "erase", "reset", "remove", "clear all",
        "factory", "uninstall", "format", "wipe", "destroy",
        "quit", "force quit", "shut down", "restart", "log out",
    ]

    private func isDangerous(_ action: DiscoveredAction) -> Bool {
        let name = (action.name ?? "").lowercased()
        return Self.dangerousPatterns.contains { name.contains($0) }
    }

    // MARK: - Tree Reading

    private func readTree(pid: pid_t) throws -> AXNode {
        var reader = AXTreeReader()
        let raw = try reader.readTree(pid: pid)
        return pipeline.prune(raw)
    }
}
