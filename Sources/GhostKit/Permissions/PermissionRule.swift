import Foundation

/// A single permission rule: allow or deny an action pattern.
///
/// Format: `Action` or `Action(specifier)`
/// Examples:
///   - `Press` — matches all press actions
///   - `Press(System Settings > content > *)` — matches press in System Settings content
///   - `Key(* cmd+s)` — matches cmd+s in any app
///   - `Type(Mail *)` — matches typing in Mail
public struct PermissionRule: Equatable, Codable {
    public let action: String
    public let specifier: String?
    public let effect: RuleEffect
    public let source: RuleSource

    public init(action: String, specifier: String? = nil, effect: RuleEffect, source: RuleSource = .defaults) {
        self.action = action.lowercased()
        self.specifier = specifier
        self.effect = effect
        self.source = source
    }

    /// Parse a rule string like "Press(System Settings > content > *)" into a PermissionRule.
    public static func parse(_ raw: String, effect: RuleEffect, source: RuleSource = .defaults) -> PermissionRule? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Check for specifier: Action(specifier)
        if let parenStart = trimmed.firstIndex(of: "("),
           let parenEnd = trimmed.lastIndex(of: ")"),
           parenEnd > parenStart
        {
            let action = String(trimmed[trimmed.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
            let specifier = String(trimmed[trimmed.index(after: parenStart)..<parenEnd]).trimmingCharacters(in: .whitespaces)
            return PermissionRule(action: action, specifier: specifier, effect: effect, source: source)
        }

        // No specifier: just the action name
        return PermissionRule(action: trimmed, specifier: nil, effect: effect, source: source)
    }

    /// Check if this rule matches a given action request.
    public func matches(action: String, app: String, target: String) -> Bool {
        // Action must match (case-insensitive)
        guard self.action == action.lowercased() || self.action == "*" else { return false }

        // No specifier = matches everything for this action
        guard let specifier = specifier else { return true }

        // Build the full path: "App > target path"
        let fullPath = "\(app) > \(target)"
        return matchesWildcard(pattern: specifier, text: fullPath)
    }

    /// Wildcard matching: `*` matches any sequence of characters within a segment,
    /// `>` is treated as a path separator.
    private func matchesWildcard(pattern: String, text: String) -> Bool {
        let patternParts = pattern.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
        let textParts = text.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }

        return matchSegments(patternParts: patternParts, textParts: textParts, pi: 0, ti: 0)
    }

    private func matchSegments(patternParts: [String], textParts: [String], pi: Int, ti: Int) -> Bool {
        // Both exhausted: match
        if pi == patternParts.count && ti == textParts.count { return true }
        // Pattern exhausted but text remains: no match
        if pi == patternParts.count { return false }

        let patternSeg = patternParts[pi]

        // Lone `*` segment matches one or more remaining text segments
        if patternSeg == "*" {
            let remaining = textParts.count - ti
            guard remaining > 0 else { return false }
            for skip in 1...remaining {
                if matchSegments(patternParts: patternParts, textParts: textParts, pi: pi + 1, ti: ti + skip) {
                    return true
                }
            }
            return false
        }

        // Text exhausted but pattern remains: no match
        if ti == textParts.count { return false }

        // Match individual segment with wildcards
        if matchSegmentWildcard(pattern: patternSeg, text: textParts[ti]) {
            return matchSegments(patternParts: patternParts, textParts: textParts, pi: pi + 1, ti: ti + 1)
        }

        return false
    }

    /// Match a single segment with `*` wildcards (e.g., "Erase *" matches "Erase All Content").
    private func matchSegmentWildcard(pattern: String, text: String) -> Bool {
        if pattern == "*" { return true }
        if !pattern.contains("*") {
            return pattern.caseInsensitiveCompare(text) == .orderedSame
        }

        // Split on * and check that all parts appear in order
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map { String($0).lowercased() }
        let textLower = text.lowercased()
        var searchStart = textLower.startIndex

        for (i, part) in parts.enumerated() {
            if part.isEmpty { continue }
            guard let range = textLower.range(of: part, range: searchStart..<textLower.endIndex) else {
                return false
            }
            // First part must be at the start if pattern doesn't start with *
            if i == 0 && !pattern.hasPrefix("*") && range.lowerBound != textLower.startIndex {
                return false
            }
            // Last part must be at the end if pattern doesn't end with *
            if i == parts.count - 1 && !pattern.hasSuffix("*") && range.upperBound != textLower.endIndex {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }
}

public enum RuleEffect: String, Codable {
    case allow
    case deny
}

public enum RuleSource: String, Codable {
    case defaults
    case managed
    case user
    case project
    case session
}
