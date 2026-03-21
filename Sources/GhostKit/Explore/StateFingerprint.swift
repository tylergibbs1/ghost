import CommonCrypto
import Foundation

/// Generates a structural fingerprint of an AX tree state.
/// Two states are "the same" if they have the same fingerprint.
///
/// The fingerprint captures the structural skeleton of the UI:
/// roles, names, and hierarchy — but NOT volatile data like
/// scroll positions, focus state, or exact text field values.
public struct StateFingerprint {
    public init() {}

    /// Generate a fingerprint for a pruned AX tree.
    public func fingerprint(_ root: AXNode) -> String {
        var hasher = ""
        buildFingerprint(root, into: &hasher, depth: 0)
        return sha256(hasher)
    }

    /// Generate a human-readable label for a state from visible headings and titles.
    public func label(_ root: AXNode) -> String {
        var parts: [String] = []

        // App name
        if root.role == "app", let name = root.name {
            parts.append(name)
        }

        // Find the most prominent heading or title in the content area
        let headings = collectByRole(root, roles: ["heading"])
        if let firstHeading = headings.first, let name = firstHeading.name {
            parts.append(name)
        }

        // Window title
        let windows = collectByRole(root, roles: ["window"])
        if let window = windows.first, let name = window.name, !name.isEmpty {
            if !parts.contains(name) {
                parts.append(name)
            }
        }

        // Active/selected navigation items
        let selected = collectSelected(root)
        for item in selected.prefix(2) {
            if let name = item.name, !parts.contains(name) {
                parts.append(name)
            }
        }

        return parts.isEmpty ? "unknown" : parts.joined(separator: " > ")
    }

    // MARK: - Fingerprint building

    /// Build a structural string ignoring volatile state.
    private func buildFingerprint(_ node: AXNode, into result: inout String, depth: Int) {
        // Include role always
        result.append("\(depth):\(node.role)")

        // Include name if it's a structural element (not a value that changes)
        if isStructuralName(node) {
            result.append("=\(node.name ?? "")")
        }

        result.append(";")

        // Recurse into children (order matters for fingerprinting)
        for child in node.children {
            buildFingerprint(child, into: &result, depth: depth + 1)
        }
    }

    /// Names that are structural (part of the UI skeleton) vs. volatile (user data).
    private func isStructuralName(_ node: AXNode) -> Bool {
        switch node.role {
        // These roles have names that define the UI structure
        case "heading", "menuItem", "tab", "item", "button", "toggle",
             "sidebar", "content", "toolbar", "menu", "menubar",
             "window", "app", "dialog", "sheet":
            return true
        // Text fields, search boxes, etc. have volatile values
        case "textfield", "search", "combobox", "text":
            return false
        default:
            return node.name != nil && node.children.isEmpty == false
        }
    }

    // MARK: - Label helpers

    private func collectByRole(_ node: AXNode, roles: Set<String>) -> [AXNode] {
        var results: [AXNode] = []
        if roles.contains(node.role) {
            results.append(node)
        }
        for child in node.children {
            results.append(contentsOf: collectByRole(child, roles: roles))
        }
        return results
    }

    private func collectSelected(_ node: AXNode) -> [AXNode] {
        var results: [AXNode] = []
        if node.state.contains(.selected) {
            results.append(node)
        }
        for child in node.children {
            results.append(contentsOf: collectSelected(child))
        }
        return results
    }

    // MARK: - Hashing

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        // Use first 12 bytes (24 hex chars) — enough to avoid collisions in app-sized state spaces
        return hash.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
