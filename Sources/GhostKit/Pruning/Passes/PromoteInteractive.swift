import Foundation

/// Ensures interactive elements are directly accessible by verifying
/// they have their available actions attached. This pass mostly benefits
/// from StripStructuralNoise and CollapseSingleChild having already
/// removed wrapper containers.
///
/// Also strips empty non-interactive leaf nodes that add no value.
struct PromoteInteractive: PruningPass {
    private static let interactiveRoles: Set<String> = [
        "button", "toggle", "textfield", "slider", "dropdown",
        "combobox", "search", "link", "menuItem", "radio",
        "disclosure", "colorWell", "tab",
    ]

    func apply(to root: AXNode, context: PruningContext) -> AXNode {
        promote(root)
        return root
    }

    private func promote(_ node: AXNode) {
        // Process children bottom-up
        for child in node.children {
            promote(child)
        }

        // Remove empty non-interactive leaf nodes
        node.children = node.children.filter { child in
            if child.children.isEmpty
                && child.name == nil
                && child.value == nil
                && !Self.interactiveRoles.contains(child.role)
                && child.role != "text"
                && child.role != "heading"
                && child.role != "image"
            {
                return false
            }
            return true
        }
    }
}
