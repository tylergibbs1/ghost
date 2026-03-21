import ArgumentParser
import Foundation
import GhostKit

struct ExploreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explore",
        abstract: "Autonomously map every reachable state and action in an app."
    )

    @Argument(help: "Application name to explore.")
    var app: String

    @Option(name: .long, help: "Maximum exploration depth. Default: 6.")
    var maxDepth: Int = 6

    @Option(name: .long, help: "Maximum states to discover. Default: 200.")
    var maxStates: Int = 200

    @Option(name: .long, help: "Maximum time in seconds. Default: 300.")
    var timeout: Int = 300

    @Flag(name: .long, help: "Include dangerous actions (Delete, Reset, etc.).")
    var dangerous: Bool = false

    @Flag(name: .long, help: "Explore text fields by focusing them.")
    var textFields: Bool = false

    @Option(name: .long, help: "Output path for .ghostmap file.")
    var output: String?

    @Flag(name: .long, help: "Show visual overlay during exploration.")
    var overlay: Bool = false

    func run() async throws {
        let blocklist = Blocklist()
        let appResolver = AppResolver()

        try blocklist.check(appName: app)
        let runningApp = try appResolver.resolve(name: app)

        print("Exploring \(runningApp.localizedName ?? app)...")
        print("  Max depth: \(maxDepth), Max states: \(maxStates), Timeout: \(timeout)s")
        if !dangerous { print("  Skipping dangerous actions (use --dangerous to include)") }
        print("")

        // Start overlay if requested
        if overlay {
            OverlayController.shared.start(config: OverlayConfig(enabled: true, statusBar: true))
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let config = ExploreConfig(
            maxDepth: maxDepth,
            maxStates: maxStates,
            maxDuration: TimeInterval(timeout),
            exploreDangerous: dangerous,
            exploreTextFields: textFields,
            onProgress: { stats, label in
                let pct = stats.actionsDiscovered > 0
                    ? Int(Double(stats.actionsExplored) / Double(stats.actionsDiscovered) * 100)
                    : 0
                print("\r  [\(stats.statesDiscovered) states, \(stats.actionsExplored)/\(stats.actionsDiscovered) actions (\(pct)%)] \(label)          ", terminator: "")
                fflush(stdout)

                if OverlayController.shared.config.enabled {
                    OverlayController.shared.logAction("explore: \(label) (\(stats.actionsExplored) actions)")
                }
            }
        )

        let engine = ExploreEngine()
        let graph = try await engine.explore(
            pid: runningApp.processIdentifier,
            appName: runningApp.localizedName ?? app,
            config: config
        )

        print("\n")

        // Save ghostmap
        let mapPath = output ?? GhostMap.defaultPath(for: runningApp.localizedName ?? app)
        try GhostMap().save(graph, to: mapPath)
        print("Saved: \(mapPath)")
        print("")

        // Print summary
        print(GhostMap().summary(graph))

        if overlay {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            OverlayController.shared.stop()
        }
    }
}

struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Search an app's ghostmap for states, actions, or parameters."
    )

    @Argument(help: "Application name (must have been explored first).")
    var app: String

    @Argument(help: "Search query, e.g. 'DNS', 'Wi-Fi toggle', 'password'. Use '*' to list all.")
    var search: String = "*"

    @Flag(name: .long, help: "Show all configurable parameters instead of searching.")
    var params: Bool = false

    func run() async throws {
        let mapPath = GhostMap.defaultPath(for: app)
        let graph = try GhostMap().load(from: mapPath)

        if params {
            let allParams = graph.allParameters()
            if allParams.isEmpty {
                print("No configurable parameters found in \(app) map.")
                return
            }
            print("Configurable parameters in \(app):")
            for param in allParams {
                let steps = param.path.map { $0.action.name ?? $0.action.role }.joined(separator: " > ")
                let nav = steps.isEmpty ? "(root)" : "via: \(steps)"
                print("  [\(param.role)] \(param.name)  \(nav)")
            }
            return
        }

        let results = graph.search(search)
        if results.isEmpty {
            print("No results for \"\(search)\" in \(app) map.")
            print("Try: ghost query \"\(app)\" --params  to see all parameters.")
            return
        }

        print("Results for \"\(search)\" in \(app):")
        for (i, result) in results.prefix(10).enumerated() {
            let kind = result.kind == .state ? "state" : "action"
            let steps = result.path.count
            print("  \(i + 1). [\(kind)] \(result.label) (\(steps) steps)")

            if !result.path.isEmpty {
                print("     Path:", terminator: "")
                for step in result.path {
                    let name = step.action.name ?? step.action.role
                    print(" → \(step.action.action) \"\(name)\"", terminator: "")
                }
                print()
            }
        }
    }
}
