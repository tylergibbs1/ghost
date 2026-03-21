import ApplicationServices
import Foundation

/// Selects an item in a list, dropdown, sidebar, or radio group.
/// If the target node is directly selectable (has AXPress), it presses it.
/// If a value is provided, searches the target's children for a matching item.
struct SelectAction {
    func execute(on node: AXNode, value: String?) throws -> ActionResult {
        guard let element = node.elementRef else {
            throw GhostError.actionFailed(action: "select", target: node.displayLabel, reason: "no element reference")
        }

        // If a value is specified, find the matching child and press it
        if let value = value {
            if let child = findChild(named: value, in: node) {
                guard let childElement = child.elementRef else {
                    throw GhostError.actionFailed(action: "select", target: child.displayLabel, reason: "no element reference")
                }
                let result = AXUIElementPerformAction(childElement, kAXPressAction as CFString)
                guard result == .success else {
                    throw GhostError.actionFailed(
                        action: "select",
                        target: child.displayLabel,
                        reason: "AXPress failed with code \(result.rawValue)"
                    )
                }
                return ActionResult(success: true, description: "selected \"\(value)\" in \(node.displayLabel)")
            }
            throw GhostError.elementNotFound(target: "\(node.displayLabel) > \(value)")
        }

        // No value specified — press the target directly (e.g., sidebar item)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            // Fallback: try setting selected attribute
            let setResult = AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, true as CFTypeRef)
            guard setResult == .success else {
                throw GhostError.actionFailed(
                    action: "select",
                    target: node.displayLabel,
                    reason: "AXPress and AXSetSelected both failed"
                )
            }
            return ActionResult(success: true, description: "selected \(node.displayLabel)")
        }

        return ActionResult(success: true, description: "selected \(node.displayLabel)")
    }

    private func findChild(named name: String, in node: AXNode) -> AXNode? {
        let nameLower = name.lowercased()
        for child in node.children {
            if let childName = child.name, childName.lowercased() == nameLower {
                return child
            }
        }
        // Fuzzy: contains match
        for child in node.children {
            if let childName = child.name, childName.lowercased().contains(nameLower) {
                return child
            }
        }
        // Recursive search
        for child in node.children {
            if let found = findChild(named: name, in: child) {
                return found
            }
        }
        return nil
    }
}
