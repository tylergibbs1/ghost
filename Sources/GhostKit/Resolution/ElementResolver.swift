import Foundation

/// Resolves a target path string to a specific AXNode in a pruned tree.
/// Uses a 4-strategy fallback chain: exact path → fuzzy path → role+name search → AXIdentifier.
public struct ElementResolver {
    private let parser = PathParser()

    public init() {}

    /// Resolve a target string against a pruned tree.
    public func resolve(target: String, in root: AXNode) throws -> AXNode {
        let segments = parser.parse(target)
        guard !segments.isEmpty else {
            throw GhostError.invalidPath(raw: target)
        }

        // Strategy 1: Exact path match
        if let node = exactMatch(segments: segments, in: root) {
            return node
        }

        // Strategy 2: Fuzzy path match
        let fuzzyResults = fuzzyPathMatch(segments: segments, in: root)
        if fuzzyResults.count == 1 {
            return fuzzyResults[0]
        }

        // Strategy 3: Role + name search (use last segments)
        let searchResults = roleNameSearch(segments: segments, in: root)
        if searchResults.count == 1 {
            return searchResults[0]
        }

        // Strategy 4: AXIdentifier fallback
        if let lastName = segments.last?.name ?? segments.last?.role {
            let idResults = identifierSearch(identifier: lastName, in: root)
            if idResults.count == 1 {
                return idResults[0]
            }
        }

        // Compile all candidates for error message
        let allCandidates = Array(Set(
            (fuzzyResults + searchResults).map { describePath(to: $0, in: root) }
        ))

        if allCandidates.isEmpty {
            throw GhostError.elementNotFound(target: target)
        }
        throw GhostError.ambiguousMatch(target: target, candidates: allCandidates)
    }

    // MARK: - Strategy 1: Exact Path Match

    /// Walk the tree matching segments in sequence.
    /// The first segment is searched for anywhere in the tree (DFS).
    /// Subsequent segments must be direct children of the previous match.
    private func exactMatch(segments: [PathSegment], in root: AXNode) -> AXNode? {
        guard let firstSegment = segments.first else { return nil }

        // Find all nodes matching the first segment anywhere in the tree
        var firstMatches: [AXNode] = []
        collectMatching(root, segment: firstSegment, exact: true, results: &firstMatches)

        // If only one segment, return if unambiguous
        if segments.count == 1 {
            return firstMatches.count == 1 ? firstMatches[0] : nil
        }

        // For each first match, walk remaining segments as strict parent→child
        var finalCandidates: [AXNode] = []
        for startNode in firstMatches {
            if let result = walkChildren(from: startNode, segments: Array(segments.dropFirst())) {
                finalCandidates.append(result)
            }
        }

        return finalCandidates.count == 1 ? finalCandidates[0] : nil
    }

    /// DFS to collect all nodes matching a segment.
    private func collectMatching(_ node: AXNode, segment: PathSegment, exact: Bool, results: inout [AXNode]) {
        if matchesSegment(node, segment: segment, exact: exact) {
            results.append(node)
        }
        for child in node.children {
            collectMatching(child, segment: segment, exact: exact, results: &results)
        }
    }

    /// Walk strict parent→child for remaining segments.
    private func walkChildren(from node: AXNode, segments: [PathSegment]) -> AXNode? {
        guard let segment = segments.first else { return node }

        let matching = node.children.filter { matchesSegment($0, segment: segment, exact: true) }
        if matching.count != 1 { return nil }

        return walkChildren(from: matching[0], segments: Array(segments.dropFirst()))
    }

    // MARK: - Strategy 2: Fuzzy Path Match

    /// Like exact match but uses fuzzy string matching for names.
    private func fuzzyPathMatch(segments: [PathSegment], in root: AXNode) -> [AXNode] {
        var candidates = [root]

        for segment in segments {
            var nextCandidates: [AXNode] = []
            for candidate in candidates {
                let matching = candidate.children.filter { matchesSegment($0, segment: segment, exact: false) }
                nextCandidates.append(contentsOf: matching)
            }
            if nextCandidates.isEmpty { return [] }
            candidates = nextCandidates
        }

        return candidates
    }

    // MARK: - Strategy 3: Role + Name Search

    /// Ignores path hierarchy. Searches the entire tree for nodes matching
    /// the last segment's role and/or name.
    private func roleNameSearch(segments: [PathSegment], in root: AXNode) -> [AXNode] {
        guard let lastSegment = segments.last else { return [] }

        var results: [AXNode] = []
        searchTree(root, segment: lastSegment, results: &results)
        return results
    }

    private func searchTree(_ node: AXNode, segment: PathSegment, results: inout [AXNode]) {
        if matchesSegment(node, segment: segment, exact: false) {
            results.append(node)
        }
        for child in node.children {
            searchTree(child, segment: segment, results: &results)
        }
    }

    // MARK: - Strategy 4: AXIdentifier Fallback

    private func identifierSearch(identifier: String, in root: AXNode) -> [AXNode] {
        var results: [AXNode] = []
        searchByIdentifier(root, identifier: identifier.lowercased(), results: &results)
        return results
    }

    private func searchByIdentifier(_ node: AXNode, identifier: String, results: inout [AXNode]) {
        if let axId = node.axIdentifier, axId.lowercased().contains(identifier) {
            results.append(node)
        }
        for child in node.children {
            searchByIdentifier(child, identifier: identifier, results: &results)
        }
    }

    // MARK: - Matching

    private func matchesSegment(_ node: AXNode, segment: PathSegment, exact: Bool) -> Bool {
        // Check role match if segment specifies a role
        if let role = segment.role {
            if exact {
                if node.role != role { return false }
            } else {
                if !node.role.lowercased().contains(role.lowercased()) { return false }
            }
        }

        // Check name match if segment specifies a name
        if let name = segment.name {
            let nodeName = node.name ?? ""
            if exact {
                if nodeName != name { return false }
            } else {
                // Fuzzy: case-insensitive contains or Levenshtein distance <= 2
                let nameLC = name.lowercased()
                let nodeLC = nodeName.lowercased()
                if !nodeLC.contains(nameLC) && !nameLC.contains(nodeLC)
                    && levenshtein(nameLC, nodeLC) > 2
                {
                    return false
                }
            }
        }

        // At least one of role or name must be specified
        return segment.role != nil || segment.name != nil
    }

    // MARK: - Path Description

    /// Build a human-readable path from root to a target node.
    public func describePath(to target: AXNode, in root: AXNode) -> String {
        var path: [String] = []
        if findPath(from: root, to: target, path: &path) {
            return path.joined(separator: " > ")
        }
        return target.displayLabel
    }

    private func findPath(from node: AXNode, to target: AXNode, path: inout [String]) -> Bool {
        let segment = node.name ?? node.role
        path.append(segment)

        if node === target {
            return true
        }

        for child in node.children {
            if findPath(from: child, to: target, path: &path) {
                return true
            }
        }

        path.removeLast()
        return false
    }

    // MARK: - Levenshtein Distance

    private func levenshtein(_ s: String, _ t: String) -> Int {
        let sArr = Array(s)
        let tArr = Array(t)
        let m = sArr.count
        let n = tArr.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = sArr[i - 1] == tArr[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }
}
