import Foundation

/// Merges consecutive sibling nodes with role "text" into a single text node.
/// Reduces token count for paragraphs and descriptions that get split into
/// multiple AXStaticText elements.
struct MergeAdjacentText: PruningPass {
    func apply(to root: AXNode, context: PruningContext) -> AXNode {
        mergeText(root)
        return root
    }

    private func mergeText(_ node: AXNode) {
        // Process children first (bottom-up)
        for child in node.children {
            mergeText(child)
        }

        // Merge consecutive text children
        var merged: [AXNode] = []
        var pendingText: [String] = []
        var pendingNode: AXNode?

        for child in node.children {
            if child.role == "text" && child.children.isEmpty {
                if let name = child.name {
                    pendingText.append(name)
                }
                if pendingNode == nil {
                    pendingNode = child
                }
            } else {
                flushPending(&merged, &pendingText, &pendingNode)
                merged.append(child)
            }
        }
        flushPending(&merged, &pendingText, &pendingNode)

        node.children = merged
    }

    private func flushPending(
        _ merged: inout [AXNode],
        _ pendingText: inout [String],
        _ pendingNode: inout AXNode?
    ) {
        guard let node = pendingNode else { return }

        if pendingText.count > 1 {
            // Merge into one text node
            node.name = pendingText.joined(separator: " ")
        }
        // Single text node or merged node — add it
        if !pendingText.isEmpty || node.name != nil {
            merged.append(node)
        }

        pendingText = []
        pendingNode = nil
    }
}
