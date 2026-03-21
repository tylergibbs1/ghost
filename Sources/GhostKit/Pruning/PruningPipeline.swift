import Foundation

/// A single transformation pass over the AXNode tree.
public protocol PruningPass {
    func apply(to root: AXNode, context: PruningContext) -> AXNode
}

/// Configuration for the pruning pipeline.
public struct PruningContext {
    public let maxItems: Int

    public init(maxItems: Int = 10) {
        self.maxItems = maxItems
    }
}

/// Runs the pruning pipeline: a fixed sequence of passes that transform
/// a raw AXNode tree into a compact, agent-friendly representation.
public struct PruningPipeline {
    private let passes: [PruningPass] = [
        StripStructuralNoise(),
        CollapseSingleChild(),
        MergeAdjacentText(),
        PromoteInteractive(),
        AnnotateState(),
        TruncateLists(),
    ]

    public init() {}

    public func prune(_ root: AXNode, context: PruningContext = PruningContext()) -> AXNode {
        passes.reduce(root) { tree, pass in
            pass.apply(to: tree, context: context)
        }
    }
}
