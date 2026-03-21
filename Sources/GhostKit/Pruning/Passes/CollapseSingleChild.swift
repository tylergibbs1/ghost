import Foundation

/// Collapses parent nodes that have exactly one child and carry no
/// semantic meaning of their own. The parent is replaced by its child.
///
/// Example: A nameless "group" containing a single "button" becomes just the "button".
///
/// Applied in a fixed-point loop (max 3 rounds) since collapsing one level
/// can create new single-child situations.
struct CollapseSingleChild: PruningPass {
    private static let maxRounds = 3

    /// Roles that should never be collapsed away even with one child,
    /// because they carry structural meaning.
    private static let preserveRoles: Set<String> = [
        "app", "window", "dialog", "sheet", "menubar",
    ]

    func apply(to root: AXNode, context: PruningContext) -> AXNode {
        var current = root
        for _ in 0..<Self.maxRounds {
            let (collapsed, changed) = collapsePass(current)
            current = collapsed
            if !changed { break }
        }
        return current
    }

    private func collapsePass(_ node: AXNode) -> (AXNode, Bool) {
        var anyChanged = false

        // Process children first (bottom-up)
        var newChildren: [AXNode] = []
        for child in node.children {
            let (collapsed, changed) = collapsePass(child)
            newChildren.append(collapsed)
            if changed { anyChanged = true }
        }
        node.children = newChildren

        // Check if this node should be collapsed into its single child
        if node.children.count == 1 && shouldCollapse(node) {
            let child = node.children[0]
            // Preserve the parent's name if the child doesn't have one
            if child.name == nil && node.name != nil {
                child.name = node.name
            }
            // Preserve the parent's elementRef if the child doesn't have one
            if child.elementRef == nil {
                child.elementRef = node.elementRef
            }
            return (child, true)
        }

        return (node, anyChanged)
    }

    private func shouldCollapse(_ node: AXNode) -> Bool {
        // Don't collapse structurally important roles
        if Self.preserveRoles.contains(node.role) { return false }
        // Don't collapse if the node has its own name (it's semantically meaningful)
        if node.name != nil { return false }
        // Don't collapse if the node has state or value
        if !node.state.isEmpty { return false }
        if node.value != nil { return false }
        return true
    }
}
