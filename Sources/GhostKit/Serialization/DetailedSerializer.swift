import Foundation

/// Serializes an AXNode tree to Ghost's detailed JSON format.
/// Includes element IDs, available actions, bounding rects, and full state metadata.
public struct DetailedSerializer {
    public init() {}

    public func serialize(_ node: AXNode) -> String {
        let dict = serializeNode(node)
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    /// Serialize to a dictionary (for embedding in larger JSON responses).
    public func serializeToDict(_ node: AXNode) -> [String: Any] {
        serializeNode(node)
    }

    private func serializeNode(_ node: AXNode) -> [String: Any] {
        var dict: [String: Any] = [
            "id": "n\(node.id)",
            "role": node.role,
        ]

        if let name = node.name {
            dict["name"] = name
        }

        if let value = node.value {
            dict["value"] = value
        }

        if !node.state.isEmpty {
            var stateDict: [String: Bool] = [:]
            for s in node.state {
                stateDict[s.rawValue] = true
            }
            dict["state"] = stateDict
        }

        if !node.actions.isEmpty {
            dict["actions"] = node.actions
        }

        if let identifier = node.axIdentifier {
            dict["axIdentifier"] = identifier
        }

        if let frame = node.frame {
            dict["frame"] = [
                "x": Int(frame.origin.x),
                "y": Int(frame.origin.y),
                "width": Int(frame.size.width),
                "height": Int(frame.size.height),
            ]
        }

        if !node.children.isEmpty {
            dict["children"] = node.children.map { serializeNode($0) }
        }

        return dict
    }
}
