import Foundation

/// Enriches nodes with human-readable state annotations.
/// Reads existing state/value and ensures they're formatted for display:
/// - Toggles/checkboxes: "on"/"off"
/// - Text fields: current value or "empty"
/// - Selected items: "selected" state
///
/// This pass works on the already-populated state from AXTreeReader,
/// adding display-friendly value strings where needed.
struct AnnotateState: PruningPass {
    func apply(to root: AXNode, context: PruningContext) -> AXNode {
        annotate(root)
        return root
    }

    private func annotate(_ node: AXNode) {
        // Enrich text fields with "empty" if no value
        if node.role == "textfield" || node.role == "search" || node.role == "combobox" {
            if node.value == nil || node.value?.isEmpty == true {
                node.value = "empty"
            }
        }

        // Enrich dropdowns with their selected value
        if node.role == "dropdown" && node.value == nil {
            // Check if any child is selected
            if let selected = node.children.first(where: { $0.state.contains(.selected) }) {
                node.value = selected.name
            }
        }

        // Recurse
        for child in node.children {
            annotate(child)
        }
    }
}
