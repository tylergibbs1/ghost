import Foundation

/// A node in the app's state graph. Represents a distinct UI state
/// (e.g., "System Settings showing the Network pane").
public final class AppState {
    /// Unique identifier for this state (hash of the pruned tree fingerprint).
    public let id: String

    /// Human-readable label derived from visible headings/titles.
    public var label: String

    /// The fingerprint used to identify this state (structural hash).
    public let fingerprint: String

    /// All actionable elements discovered in this state.
    public var actions: [DiscoveredAction]

    /// Transitions: action ID → target state ID.
    public var transitions: [String: String]

    /// The full pruned tree snapshot of this state (optional, for first visit only).
    public var treeSnapshot: String?

    /// Depth from the root state (for BFS ordering).
    public var depth: Int

    /// Number of times this state has been visited during exploration.
    public var visitCount: Int

    public init(id: String, label: String, fingerprint: String, depth: Int) {
        self.id = id
        self.label = label
        self.fingerprint = fingerprint
        self.actions = []
        self.transitions = [:]
        self.treeSnapshot = nil
        self.depth = depth
        self.visitCount = 1
    }
}

/// An actionable element discovered during exploration.
public struct DiscoveredAction: Codable {
    /// Unique ID for this action within the state.
    public let id: String

    /// The type of action: press, type, select, toggle, etc.
    public let action: String

    /// Element role (button, toggle, textfield, etc.).
    public let role: String

    /// Element name/label.
    public let name: String?

    /// Path from root to this element.
    public let path: String

    /// Whether this action has been tried during exploration.
    public var explored: Bool

    /// What kind of effect this action had.
    public var effect: ActionEffect?

    /// For typed inputs: the value type (text, number, ip_address, etc.).
    public var paramType: String?

    public init(
        id: String,
        action: String,
        role: String,
        name: String?,
        path: String
    ) {
        self.id = id
        self.action = action
        self.role = role
        self.name = name
        self.path = path
        self.explored = false
        self.effect = nil
        self.paramType = nil
    }
}

/// What happened when an action was executed.
public enum ActionEffect: String, Codable {
    case stateChange    // Navigated to a different state
    case valueToggle    // Toggled a value (on/off, checked/unchecked)
    case noChange       // Nothing observable changed
    case dialogOpened   // A sheet/dialog/popover appeared
    case dialogClosed   // A sheet/dialog was dismissed
    case textInput      // Focused a text field for input
    case menuExpanded   // A menu or dropdown expanded
    case error          // The action failed or was blocked
}

/// The complete state graph for an application.
public final class AppGraph {
    /// The application name.
    public let appName: String

    /// When this graph was built.
    public let exploredAt: Date

    /// macOS version during exploration.
    public let osVersion: String

    /// App version if detectable.
    public var appVersion: String?

    /// All discovered states, keyed by state ID.
    public var states: [String: AppState]

    /// The root state ID (state when exploration started).
    public let rootStateId: String

    /// Exploration statistics.
    public var stats: ExploreStats

    public init(appName: String, rootStateId: String) {
        self.appName = appName
        self.exploredAt = Date()
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.states = [:]
        self.rootStateId = rootStateId
        self.stats = ExploreStats()
    }

    // MARK: - Query API

    /// Find the shortest path from root to a state matching a predicate.
    public func findPath(to predicate: (AppState) -> Bool) -> [PathStep]? {
        // BFS from root
        var queue: [(stateId: String, path: [PathStep])] = [(rootStateId, [])]
        var visited = Set<String>()

        while !queue.isEmpty {
            let (currentId, currentPath) = queue.removeFirst()
            guard !visited.contains(currentId) else { continue }
            visited.insert(currentId)

            guard let state = states[currentId] else { continue }

            if predicate(state) {
                return currentPath
            }

            for (actionId, targetStateId) in state.transitions {
                guard let action = state.actions.first(where: { $0.id == actionId }) else { continue }
                let step = PathStep(
                    fromState: currentId,
                    action: action,
                    toState: targetStateId
                )
                queue.append((targetStateId, currentPath + [step]))
            }
        }

        return nil
    }

    /// Find a path to a state or action matching a search string.
    public func search(_ query: String) -> [SearchResult] {
        let queryLower = query.lowercased()
        var results: [SearchResult] = []

        for (_, state) in states {
            // Match state labels
            if state.label.lowercased().contains(queryLower) {
                if let path = findPath(to: { $0.id == state.id }) {
                    results.append(SearchResult(
                        kind: .state,
                        label: state.label,
                        path: path,
                        state: state
                    ))
                }
            }

            // Match action names within states
            for action in state.actions {
                let actionLabel = action.name ?? action.role
                if actionLabel.lowercased().contains(queryLower) {
                    if let path = findPath(to: { $0.id == state.id }) {
                        results.append(SearchResult(
                            kind: .action,
                            label: "\(state.label) > \(actionLabel)",
                            path: path,
                            state: state,
                            action: action
                        ))
                    }
                }
            }
        }

        return results.sorted { $0.path.count < $1.path.count }
    }

    /// List all configurable parameters (toggles, text fields, dropdowns).
    public func allParameters() -> [ParameterInfo] {
        var params: [ParameterInfo] = []

        for (_, state) in states {
            for action in state.actions {
                let isParam = action.role == "toggle" || action.role == "textfield"
                    || action.role == "dropdown" || action.role == "slider"
                    || action.role == "search" || action.role == "combobox"
                guard isParam else { continue }

                if let path = findPath(to: { $0.id == state.id }) {
                    params.append(ParameterInfo(
                        name: action.name ?? action.role,
                        role: action.role,
                        path: path,
                        statePath: state.label,
                        action: action
                    ))
                }
            }
        }

        return params
    }
}

/// A step in a navigation path.
public struct PathStep: Codable {
    public let fromState: String
    public let action: DiscoveredAction
    public let toState: String
}

/// A search result from the graph query API.
public struct SearchResult {
    public enum Kind { case state, action }
    public let kind: Kind
    public let label: String
    public let path: [PathStep]
    public let state: AppState
    public let action: DiscoveredAction?

    init(kind: Kind, label: String, path: [PathStep], state: AppState, action: DiscoveredAction? = nil) {
        self.kind = kind
        self.label = label
        self.path = path
        self.state = state
        self.action = action
    }
}

/// Info about a configurable parameter in the app.
public struct ParameterInfo {
    public let name: String
    public let role: String
    public let path: [PathStep]
    public let statePath: String
    public let action: DiscoveredAction
}

/// Exploration statistics.
public struct ExploreStats {
    public var statesDiscovered: Int = 0
    public var actionsDiscovered: Int = 0
    public var actionsExplored: Int = 0
    public var transitionsRecorded: Int = 0
    public var duration: TimeInterval = 0
    public var maxDepth: Int = 0
}
