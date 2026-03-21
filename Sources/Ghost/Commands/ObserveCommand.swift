import ArgumentParser
import Foundation
import GhostKit

struct ObserveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "observe",
        abstract: "Read the accessibility tree for an application or the entire desktop."
    )

    @Argument(help: "Application name to observe. Omit to list all running apps.")
    var app: String?

    @Option(name: .long, help: "Path to a subtree to focus on, e.g. 'content', 'sidebar'.")
    var focus: String?

    @Option(name: .long, help: "Output format: concise (default) or detailed.")
    var format: String = "concise"

    @Option(name: .long, help: "Maximum items in lists before truncating. Default: 10.")
    var maxItems: Int = 10

    @Flag(name: .long, help: "Show visual overlay highlighting observed elements.")
    var overlay: Bool = false

    @Option(name: .long, help: "Overlay animation speed: fast, normal, slow.")
    var speed: String = "normal"

    func run() async throws {
        let blocklist = Blocklist()
        let appResolver = AppResolver()
        let overlayCtrl = OverlayController.shared

        // Start overlay if requested
        if overlay {
            let animSpeed = AnimationSpeed(rawValue: speed) ?? .normal
            overlayCtrl.start(config: OverlayConfig(enabled: true, statusBar: true, animationSpeed: animSpeed))
            // Give the overlay windows time to appear
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // No app specified: show desktop summary
        guard let appName = app else {
            let reader = AXTreeReader()
            let desktop = reader.readDesktop()
            let pipeline = PruningPipeline()
            let pruned = pipeline.prune(desktop, context: PruningContext(maxItems: maxItems))
            print(ConciseSerializer().serialize(pruned))
            if overlay { await waitForOverlay(overlayCtrl) }
            return
        }

        // Check blocklist
        try blocklist.check(appName: appName)

        // Resolve app
        let runningApp = try appResolver.resolve(name: appName)

        // Read AX tree
        var reader = AXTreeReader()
        let tree = try reader.readTree(pid: runningApp.processIdentifier)

        // Prune
        let pipeline = PruningPipeline()
        let pruned = pipeline.prune(tree, context: PruningContext(maxItems: maxItems))

        // Apply focus filter
        let output: AXNode
        if let focusPath = focus {
            let resolver = ElementResolver()
            output = try resolver.resolve(target: focusPath, in: pruned)
        } else {
            output = pruned
        }

        // Overlay: highlight the observed subtree
        if overlay {
            overlayCtrl.logAction("observe \(appName)" + (focus.map { " > \($0)" } ?? ""))
            highlightTree(output, action: "observe", controller: overlayCtrl)
        }

        // Serialize
        switch format {
        case "detailed":
            print(DetailedSerializer().serialize(output))
        default:
            print(ConciseSerializer().serialize(output))
        }

        if overlay { await waitForOverlay(overlayCtrl) }
    }

    /// Highlight all nodes with frames in a tree.
    private func highlightTree(_ node: AXNode, action: String, controller: OverlayController) {
        if let frame = node.frame, frame.width > 0, frame.height > 0 {
            controller.showObserve(frame: frame, label: node.displayLabel)
        }
        // Only highlight the first few interactive elements to avoid noise
        let interactive = collectInteractive(node, limit: 8)
        for child in interactive {
            if let frame = child.frame, frame.width > 0, frame.height > 0 {
                controller.showObserve(frame: frame, label: child.displayLabel)
            }
        }
    }

    private func collectInteractive(_ node: AXNode, limit: Int) -> [AXNode] {
        var results: [AXNode] = []
        collectInteractiveHelper(node, results: &results, limit: limit)
        return results
    }

    private func collectInteractiveHelper(_ node: AXNode, results: inout [AXNode], limit: Int) {
        guard results.count < limit else { return }
        if !node.actions.isEmpty && node.frame != nil {
            results.append(node)
        }
        for child in node.children {
            collectInteractiveHelper(child, results: &results, limit: limit)
        }
    }

    /// Keep the overlay visible for a bit then clean up.
    private func waitForOverlay(_ controller: OverlayController) async {
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        controller.stop()
    }
}
