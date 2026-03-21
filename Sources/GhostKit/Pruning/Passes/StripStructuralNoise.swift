import Foundation

/// Removes structural/layout nodes that carry no semantic meaning.
/// Nodes with roles like "group", "scrollArea", "splitGroup", "layoutArea"
/// are removed if they have no name or identifier. Their children get
/// spliced into the parent's child list.
struct StripStructuralNoise: PruningPass {
    private static let noiseRoles: Set<String> = [
        "group",
        "scrollArea",
        "splitGroup",
        "layoutArea",
        "splitter",
        "growArea",
        "ruler",
        "relevance",
    ]

    func apply(to root: AXNode, context: PruningContext) -> AXNode {
        stripNoise(root)
        return root
    }

    private func stripNoise(_ node: AXNode) {
        // Process children bottom-up
        for child in node.children {
            stripNoise(child)
        }

        // Rebuild children list, splicing in grandchildren for noise nodes
        var newChildren: [AXNode] = []
        for child in node.children {
            if isNoise(child) {
                // Replace noise node with its children
                newChildren.append(contentsOf: child.children)
            } else {
                newChildren.append(child)
            }
        }
        node.children = newChildren
    }

    private func isNoise(_ node: AXNode) -> Bool {
        guard Self.noiseRoles.contains(node.role) else { return false }
        // Keep if it has a meaningful name or identifier
        if node.name != nil { return false }
        if node.axIdentifier != nil { return false }
        return true
    }
}
