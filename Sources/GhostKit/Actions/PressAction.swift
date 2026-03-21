import ApplicationServices
import Foundation

/// Presses a button, toggle, checkbox, menu item, or link via the AX API.
struct PressAction {
    func execute(on node: AXNode) throws -> ActionResult {
        guard let element = node.elementRef else {
            throw GhostError.actionFailed(action: "press", target: node.displayLabel, reason: "no element reference")
        }

        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            throw GhostError.actionFailed(
                action: "press",
                target: node.displayLabel,
                reason: "AXPress failed with code \(result.rawValue)"
            )
        }

        return ActionResult(success: true, description: "pressed \(node.displayLabel)")
    }
}
