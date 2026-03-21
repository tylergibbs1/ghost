import Foundation

/// A single change between two accessibility tree snapshots.
public enum DiffEntry: Equatable {
    case added(path: String, detail: String)
    case removed(path: String, detail: String)
    case changed(path: String, field: String, from: String, to: String)

    public var type: String {
        switch self {
        case .added: return "added"
        case .removed: return "removed"
        case .changed: return "changed"
        }
    }

    public var path: String {
        switch self {
        case .added(let path, _): return path
        case .removed(let path, _): return path
        case .changed(let path, _, _, _): return path
        }
    }

    /// Serialize to a dictionary for JSON output.
    public func toDict() -> [String: String] {
        switch self {
        case .added(let path, let detail):
            return ["type": "added", "path": path, "detail": detail]
        case .removed(let path, let detail):
            return ["type": "removed", "path": path, "detail": detail]
        case .changed(let path, let field, let from, let to):
            return ["type": "changed", "path": path, "field": field, "from": from, "to": to]
        }
    }

    /// Human-readable description for concise output.
    public var description: String {
        switch self {
        case .added(let path, let detail):
            return "[added] \(path): \(detail)"
        case .removed(let path, let detail):
            return "[removed] \(path): \(detail)"
        case .changed(let path, let field, let from, let to):
            return "[changed] \(path) \(field): \"\(from)\" -> \"\(to)\""
        }
    }
}
