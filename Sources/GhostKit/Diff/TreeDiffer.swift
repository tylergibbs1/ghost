import Foundation

/// Computes structural diffs between two pruned AXNode trees.
/// Matches nodes by (role, name) pairs and reports added, removed, and changed entries.
public struct TreeDiffer {
    public init() {}

    public func diff(before: AXNode, after: AXNode) -> [DiffEntry] {
        var entries: [DiffEntry] = []
        diffRecursive(before: before, after: after, pathPrefix: "", entries: &entries)
        return entries
    }

    private func diffRecursive(
        before: AXNode,
        after: AXNode,
        pathPrefix: String,
        entries: inout [DiffEntry]
    ) {
        let currentPath = buildPath(pathPrefix, node: after)

        // Compare value
        if before.value != after.value {
            entries.append(.changed(
                path: currentPath,
                field: "value",
                from: before.value ?? "",
                to: after.value ?? ""
            ))
        }

        // Compare state
        let addedStates = after.state.subtracting(before.state)
        let removedStates = before.state.subtracting(after.state)
        for state in addedStates.sorted() {
            entries.append(.changed(path: currentPath, field: state.rawValue, from: "false", to: "true"))
        }
        for state in removedStates.sorted() {
            entries.append(.changed(path: currentPath, field: state.rawValue, from: "true", to: "false"))
        }

        // Match children by (role, name) key
        let beforeChildren = indexChildren(before.children)
        let afterChildren = indexChildren(after.children)

        let beforeKeys = Set(beforeChildren.keys)
        let afterKeys = Set(afterChildren.keys)

        // Removed children
        for key in beforeKeys.subtracting(afterKeys) {
            if let nodes = beforeChildren[key] {
                for node in nodes {
                    entries.append(.removed(path: buildPath(currentPath, node: node), detail: node.displayLabel))
                }
            }
        }

        // Added children
        for key in afterKeys.subtracting(beforeKeys) {
            if let nodes = afterChildren[key] {
                for node in nodes {
                    entries.append(.added(path: buildPath(currentPath, node: node), detail: node.displayLabel))
                }
            }
        }

        // Matched children — recurse
        for key in beforeKeys.intersection(afterKeys) {
            guard let bNodes = beforeChildren[key], let aNodes = afterChildren[key] else { continue }
            let pairCount = min(bNodes.count, aNodes.count)
            for i in 0..<pairCount {
                diffRecursive(before: bNodes[i], after: aNodes[i], pathPrefix: currentPath, entries: &entries)
            }
            // Extra nodes on either side
            if aNodes.count > bNodes.count {
                for i in pairCount..<aNodes.count {
                    entries.append(.added(path: buildPath(currentPath, node: aNodes[i]), detail: aNodes[i].displayLabel))
                }
            }
            if bNodes.count > aNodes.count {
                for i in pairCount..<bNodes.count {
                    entries.append(.removed(path: buildPath(currentPath, node: bNodes[i]), detail: bNodes[i].displayLabel))
                }
            }
        }
    }

    // MARK: - Helpers

    /// Key for matching nodes: (role, name).
    private struct NodeKey: Hashable {
        let role: String
        let name: String?
    }

    /// Index children by their (role, name) key, preserving order for duplicates.
    private func indexChildren(_ children: [AXNode]) -> [NodeKey: [AXNode]] {
        var index: [NodeKey: [AXNode]] = [:]
        for child in children {
            let key = NodeKey(role: child.role, name: child.name)
            index[key, default: []].append(child)
        }
        return index
    }

    private func buildPath(_ prefix: String, node: AXNode) -> String {
        let segment = node.name ?? node.role
        if prefix.isEmpty {
            return segment
        }
        return "\(prefix) > \(segment)"
    }
}
