import Foundation

/// Manages reading and writing Ghost permission settings files.
public struct PermissionSettings {
    public init() {}

    /// Save a rule to the user settings file (~/.ghost/settings.json).
    public func saveRule(_ rule: PermissionRule, to path: String? = nil) throws {
        let settingsPath = path ?? defaultUserSettingsPath()

        var settings = loadSettings(from: settingsPath)

        // Get or create permissions dict
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        var allowList = permissions["allow"] as? [String] ?? []
        var denyList = permissions["deny"] as? [String] ?? []

        let ruleString = formatRule(rule)

        switch rule.effect {
        case .allow:
            if !allowList.contains(ruleString) {
                allowList.append(ruleString)
            }
        case .deny:
            if !denyList.contains(ruleString) {
                denyList.append(ruleString)
            }
        }

        permissions["allow"] = allowList
        permissions["deny"] = denyList
        settings["permissions"] = permissions

        try writeSettings(settings, to: settingsPath)
    }

    /// Format a rule back to its string representation.
    public func formatRule(_ rule: PermissionRule) -> String {
        let action = rule.action.prefix(1).uppercased() + rule.action.dropFirst()
        if let specifier = rule.specifier {
            return "\(action)(\(specifier))"
        }
        return action
    }

    // MARK: - Private

    private func loadSettings(from path: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return json
    }

    private func writeSettings(_ settings: [String: Any], to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func defaultUserSettingsPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ghost/settings.json"
    }
}
