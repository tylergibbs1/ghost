import Foundation

/// A segment in an element resolution path.
/// Either a role filter, a name filter, or both.
public struct PathSegment: Equatable {
    public let role: String?
    public let name: String?

    public init(role: String? = nil, name: String? = nil) {
        self.role = role
        self.name = name
    }
}

/// Parses Ghost path expressions like "content > toggle > Wi-Fi" into typed segments.
///
/// Heuristic: if a segment matches a known role, it's a role filter.
/// Otherwise it's a name filter.
///
/// Examples:
/// - "content > toggle > Wi-Fi" → [role:content, role:toggle, name:Wi-Fi]
/// - "sidebar > Network" → [role:sidebar, name:Network]
/// - "detail > Copy Password" → [role:detail, name:Copy Password]
public struct PathParser {
    public init() {}

    private static let knownRoles: Set<String> = [
        "app", "window", "dialog", "sheet", "sidebar", "content", "toolbar",
        "menu", "menubar", "menuItem", "list", "item", "row", "cell", "table",
        "outline", "column", "tabGroup", "tab",
        "button", "toggle", "textfield", "heading", "text", "search",
        "detail", "field", "link", "slider", "checkbox", "radio",
        "dropdown", "combobox", "image", "disclosure", "progress",
        "colorWell", "browser", "desktop",
    ]

    public func parse(_ raw: String) -> [PathSegment] {
        let parts = raw
            .split(separator: ">")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return [] }

        return parts.map { part in
            if Self.knownRoles.contains(part) {
                return PathSegment(role: part)
            } else {
                return PathSegment(name: part)
            }
        }
    }
}
