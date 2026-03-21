import ArgumentParser
import Foundation
import GhostKit

struct InteractCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interact",
        abstract: "Perform a UI interaction and return what changed."
    )

    @Argument(help: "Application name, or 'desktop' for system-level actions.")
    var app: String

    @Argument(help: "Action: press, type, select, key, navigate.")
    var action: String

    @Argument(help: "Target element path, e.g. 'content > toggle > Wi-Fi'.")
    var target: String

    @Option(name: .long, help: "Value for the action (text to type, shortcut string, etc.).")
    var value: String?

    @Flag(name: .long, help: "Include the full updated tree in the response.")
    var includeTree: Bool = false

    @Option(name: .long, help: "Output format for --include-tree: concise (default) or detailed.")
    var format: String = "concise"

    @Option(name: .long, help: "Maximum items in lists. Default: 10.")
    var maxItems: Int = 10

    @Option(name: .long, help: "Permission mode: plan, default, allowlist, open.")
    var mode: String?

    @Flag(name: .long, help: "Show visual overlay highlighting the target element and action.")
    var overlay: Bool = false

    @Option(name: .long, help: "Overlay animation speed: fast, normal, slow.")
    var speed: String = "normal"

    func run() async throws {
        let blocklist = Blocklist()
        let appResolver = AppResolver()
        let actionExecutor = ActionExecutor()
        let resolver = ElementResolver()
        let differ = TreeDiffer()
        let pipeline = PruningPipeline()
        let overlayCtrl = OverlayController.shared

        // Start overlay if requested
        if overlay {
            let animSpeed = AnimationSpeed(rawValue: speed) ?? .normal
            overlayCtrl.start(config: OverlayConfig(enabled: true, statusBar: true, animationSpeed: animSpeed))
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let context = PruningContext(maxItems: maxItems)
        let transactionLog = TransactionLog()

        // Set up permission engine
        let permMode: PermissionMode = mode.flatMap { PermissionMode(rawValue: $0) } ?? PermissionEngine.loadMode()
        let rules = PermissionEngine.loadFromHierarchy()
        let permissions = PermissionEngine(rules: rules, mode: permMode)

        // Parse action kind
        guard let actionKind = ActionKind(rawValue: action) else {
            throw GhostError.invalidAction(action: action, reason: "unknown action. Valid actions: \(ActionKind.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        // Permission check
        let decision = permissions.evaluate(action: action, app: app, target: target)
        switch decision {
        case .denied(let rule):
            let ruleStr = rule.map { PermissionSettings().formatRule($0) } ?? "mode: \(permMode.rawValue)"
            transactionLog.log(tool: "ghost_interact", action: action, app: app, target: target, result: "denied", rule: ruleStr)
            print("Error: Action denied by permission rule: \(ruleStr)")
            return
        case .prompt:
            // In CLI mode, just inform the user
            transactionLog.log(tool: "ghost_interact", action: action, app: app, target: target, result: "pending_approval")
            print("Error: Action \"\(action)\" on \"\(target)\" requires permission.")
            print("Add to ~/.ghost/settings.json permissions.allow or use --mode open.")
            return
        case .allowed:
            break
        }

        // Handle navigate to desktop
        if app.lowercased() == "desktop" && actionKind == .navigate {
            try blocklist.check(appName: target)
            let targetApp = try appResolver.resolve(name: target)
            let result = try actionExecutor.execute(action: .navigate, target: AXNode(id: 0, role: "app", name: target), value: nil, app: targetApp)
            transactionLog.log(tool: "ghost_interact", action: action, app: app, target: target, result: "success")
            printResult(success: true, action: action, target: target, diff: [], result: result)
            return
        }

        // Check blocklist
        try blocklist.check(appName: app)

        // Resolve app
        let runningApp = try appResolver.resolve(name: app)

        // Read pre-action tree
        var reader = AXTreeReader()
        let beforeTree = try reader.readTree(pid: runningApp.processIdentifier)
        let beforePruned = pipeline.prune(beforeTree, context: context)

        // Resolve target element
        let targetNode = try resolver.resolve(target: target, in: beforePruned)

        // Overlay: highlight target before action
        if overlay {
            overlayCtrl.highlightNode(targetNode, action: action)
            // Brief pause so the user sees the highlight before the action fires
            try await Task.sleep(nanoseconds: UInt64(overlayCtrl.config.animationSpeed.duration * 1_000_000_000))
        }

        // Execute action
        let result = try actionExecutor.execute(
            action: actionKind,
            target: targetNode,
            value: value,
            app: actionKind == .navigate ? runningApp : nil
        )

        // Wait for UI to settle
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Read post-action tree
        var postReader = AXTreeReader()
        let afterTree = try postReader.readTree(pid: runningApp.processIdentifier)
        let afterPruned = pipeline.prune(afterTree, context: context)

        // Diff
        let diff = differ.diff(before: beforePruned, after: afterPruned)

        // Overlay: show diff
        if overlay {
            overlayCtrl.showDiff(diff, tree: afterPruned)
        }

        // Log and output
        transactionLog.log(tool: "ghost_interact", action: action, app: app, target: target, result: "success")
        printResult(success: result.success, action: action, target: targetNode.displayLabel, diff: diff, result: result)

        if includeTree {
            print("\nTree:")
            switch format {
            case "detailed":
                print(DetailedSerializer().serialize(afterPruned))
            default:
                print(ConciseSerializer().serialize(afterPruned))
            }
        }

        if overlay {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s for user to see
            overlayCtrl.stop()
        }
    }

    private func printResult(success: Bool, action: String, target: String, diff: [DiffEntry], result: ActionResult) {
        print("Action: \(action) \(target)")
        print("Result: \(success ? "success" : "failed")")

        if diff.isEmpty {
            print("Diff: (no changes detected)")
        } else {
            print("Diff:")
            for entry in diff {
                print("  \(entry.description)")
            }
        }
    }
}
