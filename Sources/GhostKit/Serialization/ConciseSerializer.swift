import Foundation

/// Serializes an AXNode tree to Ghost's concise indented text format.
///
/// Example output:
/// ```
/// [app] System Settings
///   [window] System Settings
///     [sidebar]
///       [item] Wi-Fi (selected)
///     [content]
///       [toggle] Wi-Fi (on)
/// ```
public struct ConciseSerializer {
    private let indent: String

    public init(indent: String = "  ") {
        self.indent = indent
    }

    public func serialize(_ node: AXNode) -> String {
        var lines: [String] = []
        serializeNode(node, depth: 0, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private func serializeNode(_ node: AXNode, depth: Int, lines: inout [String]) {
        let prefix = String(repeating: indent, count: depth)
        let label = formatLabel(node)
        lines.append("\(prefix)\(label)")

        for child in node.children {
            serializeNode(child, depth: depth + 1, lines: &lines)
        }
    }

    private func formatLabel(_ node: AXNode) -> String {
        var parts: [String] = ["[\(node.role)]"]

        if let name = node.name {
            parts.append(name)
        }

        let annotations = buildAnnotations(node)
        if !annotations.isEmpty {
            parts.append("(\(annotations))")
        }

        return parts.joined(separator: " ")
    }

    private func buildAnnotations(_ node: AXNode) -> String {
        var annotations: [String] = []

        // Value first (on/off, field content, etc.)
        if let value = node.value {
            annotations.append(value)
        }

        // State annotations
        for s in node.state.sorted() {
            annotations.append(s.rawValue)
        }

        return annotations.joined(separator: ", ")
    }
}
