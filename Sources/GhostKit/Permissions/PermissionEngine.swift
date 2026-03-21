import Foundation

/// Permission modes that control how Ghost handles unapproved actions.
public enum PermissionMode: String, Codable {
    case plan       // Read only — all interactions blocked
    case `default`  // Prompt for each new action type
    case allowlist  // Only pre-approved actions work
    case open       // Everything allowed (sandboxed environments only)
}

/// Evaluation result for a permission check.
public enum PermissionDecision {
    case allowed(rule: PermissionRule?)
    case denied(rule: PermissionRule?)
    case prompt(action: String, app: String, target: String)
}

/// The permission engine evaluates action requests against a set of rules.
/// Deny always wins. Rules are evaluated in precedence order (managed > user > project > session).
public final class PermissionEngine {
    public private(set) var rules: [PermissionRule]
    public var mode: PermissionMode
    public var sessionRules: [PermissionRule] = []

    public init(rules: [PermissionRule] = PermissionEngine.defaultRules, mode: PermissionMode = .default) {
        self.rules = rules
        self.mode = mode
    }

    // MARK: - Evaluation

    /// Check whether an action is permitted.
    public func evaluate(action: String, app: String, target: String) -> PermissionDecision {
        // Plan mode blocks all interactions
        if mode == .plan {
            return .denied(rule: nil)
        }

        // Open mode allows everything
        if mode == .open {
            return .allowed(rule: nil)
        }

        // Observe and Snapshot are always allowed (read operations)
        let actionLower = action.lowercased()
        if actionLower == "observe" || actionLower == "snapshot" {
            return .allowed(rule: nil)
        }

        // Check all rules (deny wins over allow)
        let allRules = rules + sessionRules
        var bestAllow: PermissionRule?
        var bestDeny: PermissionRule?

        for rule in allRules {
            guard rule.matches(action: actionLower, app: app, target: target) else { continue }
            switch rule.effect {
            case .deny:
                bestDeny = rule
            case .allow:
                if bestAllow == nil { bestAllow = rule }
            }
        }

        // Deny always wins
        if let deny = bestDeny {
            return .denied(rule: deny)
        }

        // Explicit allow
        if let allow = bestAllow {
            return .allowed(rule: allow)
        }

        // No matching rule
        switch mode {
        case .allowlist:
            return .denied(rule: nil)
        case .default:
            return .prompt(action: action, app: app, target: target)
        case .open:
            return .allowed(rule: nil)
        case .plan:
            return .denied(rule: nil)
        }
    }

    // MARK: - Rule Management

    /// Add a session-scoped rule (e.g., from "Allow for session" prompt).
    public func addSessionRule(_ rule: PermissionRule) {
        sessionRules.append(rule)
    }

    /// Add a persistent rule and save to settings file.
    public func addPersistentRule(_ rule: PermissionRule) {
        rules.append(rule)
    }

    // MARK: - Settings Loading

    /// Load rules from a settings file.
    public static func loadRules(from path: String, source: RuleSource) -> [PermissionRule] {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let permissions = json["permissions"] as? [String: Any]
        else { return [] }

        var rules: [PermissionRule] = []

        if let allowList = permissions["allow"] as? [String] {
            for raw in allowList {
                if let rule = PermissionRule.parse(raw, effect: .allow, source: source) {
                    rules.append(rule)
                }
            }
        }

        if let denyList = permissions["deny"] as? [String] {
            for raw in denyList {
                if let rule = PermissionRule.parse(raw, effect: .deny, source: source) {
                    rules.append(rule)
                }
            }
        }

        return rules
    }

    /// Load rules from the settings hierarchy: managed > user > project.
    public static func loadFromHierarchy(projectPath: String? = nil) -> [PermissionRule] {
        var rules: [PermissionRule] = []

        // Managed settings (highest priority)
        let managedPath = "/Library/Application Support/Ghost/settings.json"
        rules.append(contentsOf: loadRules(from: managedPath, source: .managed))

        // User settings
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let userPath = "\(home)/.ghost/settings.json"
        rules.append(contentsOf: loadRules(from: userPath, source: .user))

        // Project settings (lowest priority)
        if let projectPath = projectPath {
            let projSettingsPath = "\(projectPath)/.ghost/settings.json"
            rules.append(contentsOf: loadRules(from: projSettingsPath, source: .project))
        }

        // If no rules loaded, use defaults
        if rules.isEmpty {
            return defaultRules
        }

        return rules
    }

    /// Load mode from settings hierarchy.
    public static func loadMode(projectPath: String? = nil) -> PermissionMode {
        let paths: [String] = {
            var p: [String] = []
            p.append("/Library/Application Support/Ghost/settings.json")
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            p.append("\(home)/.ghost/settings.json")
            if let proj = projectPath {
                p.append("\(proj)/.ghost/settings.json")
            }
            return p
        }()

        for path in paths {
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modeStr = json["defaultMode"] as? String,
                  let mode = PermissionMode(rawValue: modeStr)
            else { continue }
            return mode
        }

        return .default
    }

    // MARK: - Defaults

    public static let defaultRules: [PermissionRule] = [
        // Read operations always allowed
        PermissionRule(action: "observe", effect: .allow, source: .defaults),
        PermissionRule(action: "snapshot", effect: .allow, source: .defaults),
        PermissionRule(action: "scroll", effect: .allow, source: .defaults),
        PermissionRule(action: "navigate", effect: .allow, source: .defaults),
        // Dangerous operations denied by default
        PermissionRule(action: "press", specifier: "* > * > Delete", effect: .deny, source: .defaults),
        PermissionRule(action: "press", specifier: "* > * > Erase *", effect: .deny, source: .defaults),
        PermissionRule(action: "press", specifier: "* > * > Reset *", effect: .deny, source: .defaults),
        PermissionRule(action: "key", specifier: "* cmd+q", effect: .deny, source: .defaults),
        PermissionRule(action: "drag", effect: .deny, source: .defaults),
    ]
}
