import Foundation
import GhostKit

/// MCP (Model Context Protocol) server for Ghost.
/// Exposes ghost_observe, ghost_interact, and ghost_snapshot as MCP tools
/// over stdin/stdout using JSON-RPC 2.0.
struct MCPServer {
    private let blocklist = Blocklist()
    private let appResolver = AppResolver()
    private let actionExecutor = ActionExecutor()
    private let resolver = ElementResolver()
    private let differ = TreeDiffer()
    private let pipeline = PruningPipeline()
    private let permissionEngine: PermissionEngine
    private let transactionLog: TransactionLog
    private let snapshotStore = SnapshotStore()

    init(permissionEngine: PermissionEngine? = nil) {
        self.permissionEngine = permissionEngine ?? PermissionEngine()
        self.transactionLog = TransactionLog()
    }

    func run() async throws {
        // Read from stdin line by line
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                writeError(id: nil, code: -32700, message: "Parse error")
                continue
            }

            let id = json["id"]
            let method = json["method"] as? String ?? ""

            do {
                let result = try await handleMethod(method: method, params: json["params"] as? [String: Any] ?? [:])
                writeResult(id: id, result: result)
            } catch let error as GhostError {
                writeError(id: id, code: -32000, message: error.description)
            } catch {
                writeError(id: id, code: -32603, message: error.localizedDescription)
            }
        }
    }

    // MARK: - Method Dispatch

    private func handleMethod(method: String, params: [String: Any]) async throws -> Any {
        switch method {
        case "initialize":
            return initializeResponse()
        case "tools/list":
            return toolsList()
        case "tools/call":
            return try await toolsCall(params: params)
        case "notifications/initialized":
            return [String: Any]()  // Acknowledge
        default:
            throw GhostError.invalidAction(action: method, reason: "unknown MCP method")
        }
    }

    // MARK: - Initialize

    private func initializeResponse() -> [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [
                    "listChanged": false
                ]
            ],
            "serverInfo": [
                "name": "ghost",
                "version": "0.1.0",
            ],
        ]
    }

    // MARK: - Tools List

    private func toolsList() -> [String: Any] {
        [
            "tools": [
                ghostObserveTool(),
                ghostInteractTool(),
                ghostSnapshotTool(),
            ]
        ]
    }

    private func ghostObserveTool() -> [String: Any] {
        [
            "name": "ghost_observe",
            "description": "Returns the current accessibility tree for one or all macOS applications. Use this tool ONLY when you need to read GUI state that is not accessible via bash or CLI tools. Ghost is for GUI-only apps (System Settings, 1Password, Figma, native Apple apps) and for reading UI state. CLI apps like Terminal are blocklisted. Returns a pruned, token-efficient tree. Use 'focus' to zoom into a subtree. When called with no app, returns a summary of all running apps (~200 tokens).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "app": [
                        "type": "string",
                        "description": "Application name to observe. Omit to list all running apps.",
                    ],
                    "focus": [
                        "type": "string",
                        "description": "Path to a subtree to zoom into, e.g. 'content', 'sidebar'.",
                    ],
                    "format": [
                        "type": "string",
                        "enum": ["concise", "detailed"],
                        "description": "Output format. concise (default): indented text. detailed: JSON with IDs and actions.",
                    ],
                    "max_items": [
                        "type": "integer",
                        "description": "Maximum items in lists before truncating. Default: 10.",
                    ],
                ],
            ],
        ]
    }

    private func ghostInteractTool() -> [String: Any] {
        [
            "name": "ghost_interact",
            "description": "Performs a UI interaction on a macOS application and returns what changed. Use ONLY for GUI interactions that cannot be done via bash or CLI. Targets elements by accessibility tree path, not coordinates. Returns a structural diff.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "app": [
                        "type": "string",
                        "description": "Application name, or 'desktop' for system-level actions.",
                    ],
                    "action": [
                        "type": "string",
                        "enum": ["press", "type", "select", "key", "scroll", "navigate"],
                        "description": "The kind of interaction.",
                    ],
                    "target": [
                        "type": "string",
                        "description": "Accessibility tree path to the target element.",
                    ],
                    "value": [
                        "type": "string",
                        "description": "Value for the action (text to type, shortcut string, etc.).",
                    ],
                    "include_tree": [
                        "type": "boolean",
                        "description": "Include the full updated tree after the action. Default: false.",
                    ],
                ],
                "required": ["app", "action", "target"],
            ],
        ]
    }

    private func ghostSnapshotTool() -> [String: Any] {
        [
            "name": "ghost_snapshot",
            "description": "Manages saved accessibility tree states. Use 'capture' to save state before a workflow. Use 'compare' to diff current state against a snapshot. Use 'check' for boolean match.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "app": [
                        "type": "string",
                        "description": "Application name.",
                    ],
                    "action": [
                        "type": "string",
                        "enum": ["capture", "compare", "check"],
                        "description": "Snapshot action.",
                    ],
                    "label": [
                        "type": "string",
                        "description": "Short name for this snapshot.",
                    ],
                ],
                "required": ["app", "action", "label"],
            ],
        ]
    }

    // MARK: - Tools Call

    private func toolsCall(params: [String: Any]) async throws -> [String: Any] {
        guard let toolName = params["name"] as? String else {
            throw GhostError.invalidAction(action: "tools/call", reason: "missing tool name")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]

        let content: [[String: Any]]

        switch toolName {
        case "ghost_observe":
            let text = try handleObserve(args)
            content = [["type": "text", "text": text]]
        case "ghost_interact":
            let text = try await handleInteract(args)
            content = [["type": "text", "text": text]]
        case "ghost_snapshot":
            let text = try handleSnapshot(args)
            content = [["type": "text", "text": text]]
        default:
            throw GhostError.invalidAction(action: toolName, reason: "unknown tool")
        }

        return ["content": content]
    }

    // MARK: - ghost_observe

    private func handleObserve(_ args: [String: Any]) throws -> String {
        let appName = args["app"] as? String
        let focusPath = args["focus"] as? String
        let format = args["format"] as? String ?? "concise"
        let maxItems = args["max_items"] as? Int ?? 10
        let context = PruningContext(maxItems: maxItems)

        guard let appName = appName else {
            let reader = AXTreeReader()
            let desktop = reader.readDesktop()
            let pruned = pipeline.prune(desktop, context: context)
            return ConciseSerializer().serialize(pruned)
        }

        try blocklist.check(appName: appName)
        let runningApp = try appResolver.resolve(name: appName)

        var reader = AXTreeReader()
        let tree = try reader.readTree(pid: runningApp.processIdentifier)
        let pruned = pipeline.prune(tree, context: context)

        let output: AXNode
        if let focusPath = focusPath {
            output = try resolver.resolve(target: focusPath, in: pruned)
        } else {
            output = pruned
        }

        switch format {
        case "detailed":
            return DetailedSerializer().serialize(output)
        default:
            return ConciseSerializer().serialize(output)
        }
    }

    // MARK: - ghost_interact

    private func handleInteract(_ args: [String: Any]) async throws -> String {
        guard let appName = args["app"] as? String else {
            throw GhostError.invalidAction(action: "interact", reason: "app is required")
        }
        guard let actionStr = args["action"] as? String,
              let actionKind = ActionKind(rawValue: actionStr)
        else {
            throw GhostError.invalidAction(action: "interact", reason: "invalid action")
        }
        guard let target = args["target"] as? String else {
            throw GhostError.invalidAction(action: "interact", reason: "target is required")
        }

        let value = args["value"] as? String
        let includeTree = args["include_tree"] as? Bool ?? false
        let maxItems = args["max_items"] as? Int ?? 10
        let context = PruningContext(maxItems: maxItems)

        // Permission check
        let decision = permissionEngine.evaluate(action: actionStr, app: appName, target: target)
        switch decision {
        case .denied(let rule):
            let ruleStr = rule.map { PermissionSettings().formatRule($0) } ?? "mode: \(permissionEngine.mode.rawValue)"
            transactionLog.log(tool: "ghost_interact", action: actionStr, app: appName, target: target, result: "denied", rule: ruleStr)
            return "Action denied: \(actionStr) on \(target)\nRule: \(ruleStr)\nUpdate permissions in .ghost/settings.json to allow it."
        case .prompt:
            transactionLog.log(tool: "ghost_interact", action: actionStr, app: appName, target: target, result: "pending_approval")
            return "Action requires approval: \(actionStr) on \(target) in \(appName)\nThis action is not in the allowlist. Add it to .ghost/settings.json permissions.allow to permit it."
        case .allowed:
            break
        }

        // Handle desktop navigate
        if appName.lowercased() == "desktop" && actionKind == .navigate {
            try blocklist.check(appName: target)
            let targetApp = try appResolver.resolve(name: target)
            _ = try actionExecutor.execute(action: .navigate, target: AXNode(id: 0, role: "app", name: target), value: nil, app: targetApp)
            transactionLog.log(tool: "ghost_interact", action: actionStr, app: appName, target: target, result: "success")
            return "Action: navigate \(target)\nResult: success"
        }

        try blocklist.check(appName: appName)
        let runningApp = try appResolver.resolve(name: appName)

        // Pre-action tree
        var reader = AXTreeReader()
        let beforeTree = try reader.readTree(pid: runningApp.processIdentifier)
        let beforePruned = pipeline.prune(beforeTree, context: context)

        let targetNode = try resolver.resolve(target: target, in: beforePruned)

        _ = try actionExecutor.execute(
            action: actionKind,
            target: targetNode,
            value: value,
            app: actionKind == .navigate ? runningApp : nil
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        // Post-action tree
        var postReader = AXTreeReader()
        let afterTree = try postReader.readTree(pid: runningApp.processIdentifier)
        let afterPruned = pipeline.prune(afterTree, context: context)

        let diff = differ.diff(before: beforePruned, after: afterPruned)

        transactionLog.log(tool: "ghost_interact", action: actionStr, app: appName, target: target, result: "success")

        var output = "Action: \(actionStr) \(targetNode.displayLabel)\nResult: success\n"
        if diff.isEmpty {
            output += "Diff: (no changes detected)"
        } else {
            output += "Diff:\n"
            for entry in diff {
                output += "  \(entry.description)\n"
            }
        }

        if includeTree {
            output += "\nTree:\n"
            output += ConciseSerializer().serialize(afterPruned)
        }

        return output
    }

    // MARK: - ghost_snapshot

    private func handleSnapshot(_ args: [String: Any]) throws -> String {
        guard let appName = args["app"] as? String else {
            throw GhostError.invalidAction(action: "snapshot", reason: "app is required")
        }
        guard let action = args["action"] as? String else {
            throw GhostError.invalidAction(action: "snapshot", reason: "action is required")
        }
        guard let label = args["label"] as? String else {
            throw GhostError.invalidAction(action: "snapshot", reason: "label is required")
        }

        try blocklist.check(appName: appName)
        let runningApp = try appResolver.resolve(name: appName)

        var reader = AXTreeReader()
        let tree = try reader.readTree(pid: runningApp.processIdentifier)
        let pruned = pipeline.prune(tree)

        switch action {
        case "capture":
            snapshotStore.capture(app: appName, label: label, tree: pruned)
            return "Snapshot \"\(label)\" captured for \(appName)."

        case "compare":
            let diff = try snapshotStore.compare(app: appName, label: label, currentTree: pruned)
            if diff.isEmpty {
                return "No changes since snapshot \"\(label)\"."
            }
            var output = "Changes since snapshot \"\(label)\":\n"
            for entry in diff {
                output += "  \(entry.description)\n"
            }
            return output

        case "check":
            let matches = try snapshotStore.check(app: appName, label: label, currentTree: pruned)
            return matches
                ? "Current state matches snapshot \"\(label)\"."
                : "Current state does NOT match snapshot \"\(label)\"."

        default:
            throw GhostError.invalidAction(action: action, reason: "unknown snapshot action")
        }
    }

    // MARK: - JSON-RPC Response Writing

    private func writeResult(id: Any?, result: Any) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
        ]
        if let id = id {
            response["id"] = id
        }
        writeJSON(response)
    }

    private func writeError(id: Any?, code: Int, message: String) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        if let id = id {
            response["id"] = id
        }
        writeJSON(response)
    }

    private func writeJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return }
        print(json)
        fflush(stdout)
    }
}
