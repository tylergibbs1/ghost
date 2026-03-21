import Foundation

public enum GhostError: Error, CustomStringConvertible {
    case blockedApp(name: String)
    case appNotFound(name: String)
    case appNotRunning(name: String)
    case axPermissionDenied
    case axError(code: Int32, context: String)
    case elementNotFound(target: String)
    case ambiguousMatch(target: String, candidates: [String])
    case invalidAction(action: String, reason: String)
    case invalidPath(raw: String)
    case actionFailed(action: String, target: String, reason: String)

    public var description: String {
        switch self {
        case .blockedApp(let name):
            return "\(name) is a CLI application. Use bash instead. Ghost is for GUI-only apps where no CLI alternative exists."
        case .appNotFound(let name):
            return "No running application found matching \"\(name)\"."
        case .appNotRunning(let name):
            return "\"\(name)\" is not currently running."
        case .axPermissionDenied:
            return "Accessibility permission denied. Grant access in System Settings > Privacy & Security > Accessibility."
        case .axError(let code, let context):
            return "Accessibility API error (code \(code)): \(context)"
        case .elementNotFound(let target):
            return "No element found matching \"\(target)\"."
        case .ambiguousMatch(let target, let candidates):
            let list = candidates.map { "  - \($0)" }.joined(separator: "\n")
            return "Multiple elements match \"\(target)\". Be more specific:\n\(list)"
        case .invalidAction(let action, let reason):
            return "Invalid action \"\(action)\": \(reason)"
        case .invalidPath(let raw):
            return "Invalid path: \"\(raw)\""
        case .actionFailed(let action, let target, let reason):
            return "Action \"\(action)\" on \"\(target)\" failed: \(reason)"
        }
    }

    public var errorCode: String {
        switch self {
        case .blockedApp: return "blocked_app"
        case .appNotFound: return "app_not_found"
        case .appNotRunning: return "app_not_running"
        case .axPermissionDenied: return "permission_denied"
        case .axError: return "ax_error"
        case .elementNotFound: return "element_not_found"
        case .ambiguousMatch: return "ambiguous_match"
        case .invalidAction: return "invalid_action"
        case .invalidPath: return "invalid_path"
        case .actionFailed: return "action_failed"
        }
    }
}
