import ArgumentParser
import Foundation
import GhostKit

@main
struct GhostCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ghost",
        abstract: "The last mile for AI agents on macOS. Reads the accessibility tree for GUI-only apps.",
        version: "0.3.0",
        subcommands: [
            ObserveCommand.self,
            InteractCommand.self,
            SnapshotCommand.self,
            ServeCommand.self,
            TransportCommand.self,
            OverlayDemoCommand.self,
        ]
    )
}

struct TransportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transport",
        abstract: "Run in stdin/stdout JSON transport mode for agent frameworks."
    )

    func run() async throws {
        let transport = JSONTransport()
        try await transport.run()
    }
}

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run Ghost as a server (MCP or HTTP)."
    )

    @Flag(name: .long, help: "Run as an MCP server over stdin/stdout.")
    var mcp: Bool = false

    @Option(name: .long, help: "Permission mode: plan, default, allowlist, open.")
    var mode: String?

    @Flag(name: .long, help: "Show visual overlay for all actions.")
    var overlay: Bool = false

    func run() async throws {
        if overlay {
            OverlayController.shared.start(config: OverlayConfig(enabled: true, statusBar: true))
        }

        if mcp {
            let permMode: PermissionMode = mode.flatMap { PermissionMode(rawValue: $0) } ?? .default
            let engine = PermissionEngine(mode: permMode)
            let server = MCPServer(permissionEngine: engine)
            try await server.run()
        } else {
            print("Error: specify --mcp for MCP server mode. HTTP server not yet implemented.")
        }
    }
}
