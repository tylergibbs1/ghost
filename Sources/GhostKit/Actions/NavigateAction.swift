import AppKit
import Foundation

/// Brings an application to the foreground.
struct NavigateAction {
    func execute(app: NSRunningApplication) throws -> ActionResult {
        let success = app.activate()
        guard success else {
            throw GhostError.actionFailed(
                action: "navigate",
                target: app.localizedName ?? "unknown",
                reason: "failed to activate application"
            )
        }
        return ActionResult(success: true, description: "navigated to \(app.localizedName ?? "unknown")")
    }
}
