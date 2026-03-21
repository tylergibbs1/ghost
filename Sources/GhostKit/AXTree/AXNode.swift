import ApplicationServices
import Foundation

/// A node in Ghost's in-memory representation of the macOS accessibility tree.
/// Built from AXUIElement data, transformed by pruning passes, consumed by serializers and diffing.
public final class AXNode {
    public let id: Int
    public var role: String
    public var name: String?
    public var value: String?
    public var state: Set<NodeState>
    public var actions: [String]
    public var axIdentifier: String?
    public var children: [AXNode]
    public var frame: CGRect?

    /// Retained for action execution. Not used in equality/hashing.
    public var elementRef: AXUIElement?

    public init(
        id: Int,
        role: String,
        name: String? = nil,
        value: String? = nil,
        state: Set<NodeState> = [],
        actions: [String] = [],
        axIdentifier: String? = nil,
        children: [AXNode] = [],
        frame: CGRect? = nil,
        elementRef: AXUIElement? = nil
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.value = value
        self.state = state
        self.actions = actions
        self.axIdentifier = axIdentifier
        self.children = children
        self.frame = frame
        self.elementRef = elementRef
    }

    /// Deep copy, assigning new IDs starting from the given counter.
    public func deepCopy(idCounter: inout Int) -> AXNode {
        let newId = idCounter
        idCounter += 1
        return AXNode(
            id: newId,
            role: role,
            name: name,
            value: value,
            state: state,
            actions: actions,
            axIdentifier: axIdentifier,
            children: children.map { $0.deepCopy(idCounter: &idCounter) },
            frame: frame,
            elementRef: elementRef
        )
    }

    /// The display label for this node: "[role] name (state)" or "[role] name".
    public var displayLabel: String {
        var parts: [String] = ["[\(role)]"]
        if let name = name {
            parts.append(name)
        }
        let stateStr = stateAnnotation
        if !stateStr.isEmpty {
            parts.append("(\(stateStr))")
        }
        return parts.joined(separator: " ")
    }

    /// Human-readable state annotation: "on", "selected", "disabled", etc.
    public var stateAnnotation: String {
        var annotations: [String] = []
        if let value = value {
            annotations.append(value)
        }
        for s in state.sorted(by: { $0.rawValue < $1.rawValue }) {
            annotations.append(s.rawValue)
        }
        return annotations.joined(separator: ", ")
    }

    /// The path segment for this node: role if name is nil, name otherwise.
    public var pathSegment: String {
        name ?? role
    }
}

extension AXNode: Equatable {
    public static func == (lhs: AXNode, rhs: AXNode) -> Bool {
        lhs.role == rhs.role
            && lhs.name == rhs.name
            && lhs.value == rhs.value
            && lhs.state == rhs.state
            && lhs.actions == rhs.actions
            && lhs.children == rhs.children
    }
}

extension AXNode: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(role)
        hasher.combine(name)
        hasher.combine(value)
        hasher.combine(state)
    }
}

public enum NodeState: String, Hashable, Sendable, Comparable {
    case selected
    case disabled
    case expanded
    case focused
    case hidden
    case required

    public static func < (lhs: NodeState, rhs: NodeState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
