import AppKit
import ApplicationServices
import Foundation

/// The kind of interaction to perform.
public enum ActionKind: String, CaseIterable {
    case press
    case type
    case select
    case key
    case navigate
    case scroll
    case drag
}

/// Result of an action execution.
public struct ActionResult {
    public let success: Bool
    public let description: String

    public init(success: Bool, description: String) {
        self.success = success
        self.description = description
    }
}

/// Dispatches action requests to specific handlers.
public struct ActionExecutor {
    public init() {}

    public func execute(
        action: ActionKind,
        target: AXNode,
        value: String?,
        app: NSRunningApplication? = nil
    ) throws -> ActionResult {
        switch action {
        case .press:
            return try PressAction().execute(on: target)
        case .type:
            guard let text = value else {
                throw GhostError.invalidAction(action: "type", reason: "value is required for type action")
            }
            return try TypeAction().execute(on: target, text: text)
        case .select:
            return try SelectAction().execute(on: target, value: value)
        case .key:
            guard let shortcut = value else {
                throw GhostError.invalidAction(action: "key", reason: "value is required for key action (e.g. 'cmd+s')")
            }
            return try KeyAction().execute(on: target, shortcut: shortcut)
        case .navigate:
            guard let app = app else {
                throw GhostError.invalidAction(action: "navigate", reason: "app is required for navigate action")
            }
            return try NavigateAction().execute(app: app)
        case .scroll:
            throw GhostError.invalidAction(action: "scroll", reason: "scroll action not yet implemented")
        case .drag:
            throw GhostError.invalidAction(action: "drag", reason: "drag action not yet implemented")
        }
    }
}
