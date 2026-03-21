import ApplicationServices
import Foundation

/// Types text into a text field by setting its AXValue attribute.
struct TypeAction {
    func execute(on node: AXNode, text: String) throws -> ActionResult {
        guard let element = node.elementRef else {
            throw GhostError.actionFailed(action: "type", target: node.displayLabel, reason: "no element reference")
        }

        // First, try to focus the element
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)

        // Set the value
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        guard result == .success else {
            throw GhostError.actionFailed(
                action: "type",
                target: node.displayLabel,
                reason: "AXSetValue failed with code \(result.rawValue)"
            )
        }

        // Confirm the value (for fields that need explicit confirmation)
        AXUIElementPerformAction(element, kAXConfirmAction as CFString)

        return ActionResult(success: true, description: "typed \"\(text)\" into \(node.displayLabel)")
    }
}
