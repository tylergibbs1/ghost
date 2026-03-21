import Foundation

/// Truncates long lists of same-role children to `maxItems`,
/// appending a summary node with the total count.
struct TruncateLists: PruningPass {
    func apply(to root: AXNode, context: PruningContext) -> AXNode {
        truncate(root, maxItems: context.maxItems)
        return root
    }

    private func truncate(_ node: AXNode, maxItems: Int) {
        // Recurse first
        for child in node.children {
            truncate(child, maxItems: maxItems)
        }

        // Check if children form a list-like pattern (3+ children with the same role)
        guard node.children.count > maxItems else { return }

        let roleCounts = Dictionary(grouping: node.children, by: { $0.role })
        for (role, group) in roleCounts {
            guard group.count > maxItems else { continue }

            // This is a list-like group. Truncate.
            let total = group.count
            var kept = 0
            var newChildren: [AXNode] = []

            for child in node.children {
                if child.role == role {
                    if kept < maxItems {
                        newChildren.append(child)
                        kept += 1
                    }
                    // Skip the rest
                } else {
                    newChildren.append(child)
                }
            }

            // Add summary node
            let remaining = total - maxItems
            let summary = AXNode(
                id: -1,
                role: "text",
                name: "... and \(remaining) more \(role) items (showing \(maxItems) of \(total))"
            )
            newChildren.append(summary)

            node.children = newChildren
            return  // Only truncate one role group per node
        }
    }
}
