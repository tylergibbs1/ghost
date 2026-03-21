import Foundation
import GhostKit

/// Newline-delimited JSON transport over stdin/stdout.
/// Each line is a JSON request; each response is a single JSON line.
struct JSONTransport {
    private let blocklist = Blocklist()
    private let appResolver = AppResolver()
    private let actionExecutor = ActionExecutor()
    private let resolver = ElementResolver()
    private let differ = TreeDiffer()
    private let pipeline = PruningPipeline()

    func run() async throws {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }

            let response: [String: Any]
            do {
                guard let data = line.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let command = json["command"] as? String
                else {
                    response = errorResponse(code: "invalid_request", message: "Invalid JSON request")
                    writeResponse(response)
                    continue
                }

                if command == "exit" {
                    break
                }

                response = try await handleRequest(command: command, json: json)
            } catch let error as GhostError {
                response = errorResponse(code: error.errorCode, message: error.description)
            } catch {
                response = errorResponse(code: "internal_error", message: error.localizedDescription)
            }

            writeResponse(response)
        }
    }

    private func handleRequest(command: String, json: [String: Any]) async throws -> [String: Any] {
        switch command {
        case "observe":
            return try handleObserve(json)
        case "interact":
            return try await handleInteract(json)
        default:
            return errorResponse(code: "unknown_command", message: "Unknown command: \(command)")
        }
    }

    // MARK: - Observe

    private func handleObserve(_ json: [String: Any]) throws -> [String: Any] {
        let appName = json["app"] as? String
        let focusPath = json["focus"] as? String
        let format = json["format"] as? String ?? "concise"
        let maxItems = json["maxItems"] as? Int ?? 10
        let context = PruningContext(maxItems: maxItems)

        // No app: desktop summary
        guard let appName = appName else {
            let reader = AXTreeReader()
            let desktop = reader.readDesktop()
            let pruned = pipeline.prune(desktop, context: context)
            return successResponse(tree: pruned, format: format)
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

        return successResponse(tree: output, format: format)
    }

    // MARK: - Interact

    private func handleInteract(_ json: [String: Any]) async throws -> [String: Any] {
        guard let appName = json["app"] as? String else {
            return errorResponse(code: "missing_param", message: "app is required")
        }
        guard let actionStr = json["action"] as? String,
              let actionKind = ActionKind(rawValue: actionStr)
        else {
            return errorResponse(code: "invalid_action", message: "Invalid or missing action")
        }
        guard let target = json["target"] as? String else {
            return errorResponse(code: "missing_param", message: "target is required")
        }

        let value = json["value"] as? String
        let includeTree = json["includeTree"] as? Bool ?? false
        let maxItems = json["maxItems"] as? Int ?? 10
        let context = PruningContext(maxItems: maxItems)

        // Handle desktop navigate
        if appName.lowercased() == "desktop" && actionKind == .navigate {
            try blocklist.check(appName: target)
            let targetApp = try appResolver.resolve(name: target)
            _ = try actionExecutor.execute(action: .navigate, target: AXNode(id: 0, role: "app", name: target), value: nil, app: targetApp)
            return ["status": "success", "action": actionStr, "target": target, "diff": [Any]()]
        }

        try blocklist.check(appName: appName)
        let runningApp = try appResolver.resolve(name: appName)

        // Pre-action tree
        var reader = AXTreeReader()
        let beforeTree = try reader.readTree(pid: runningApp.processIdentifier)
        let beforePruned = pipeline.prune(beforeTree, context: context)

        // Resolve and execute
        let targetNode = try resolver.resolve(target: target, in: beforePruned)
        _ = try actionExecutor.execute(
            action: actionKind,
            target: targetNode,
            value: value,
            app: actionKind == .navigate ? runningApp : nil
        )

        // Wait for UI to settle
        try await Task.sleep(nanoseconds: 50_000_000)

        // Post-action tree
        var postReader = AXTreeReader()
        let afterTree = try postReader.readTree(pid: runningApp.processIdentifier)
        let afterPruned = pipeline.prune(afterTree, context: context)

        // Diff
        let diff = differ.diff(before: beforePruned, after: afterPruned)

        var response: [String: Any] = [
            "status": "success",
            "action": actionStr,
            "target": targetNode.displayLabel,
            "diff": diff.map { $0.toDict() },
        ]

        if includeTree {
            let format = json["format"] as? String ?? "concise"
            if format == "detailed" {
                response["tree"] = DetailedSerializer().serializeToDict(afterPruned)
            } else {
                response["output"] = ConciseSerializer().serialize(afterPruned)
            }
        }

        return response
    }

    // MARK: - Response Helpers

    private func successResponse(tree: AXNode, format: String) -> [String: Any] {
        if format == "detailed" {
            return [
                "status": "success",
                "tree": DetailedSerializer().serializeToDict(tree),
            ]
        } else {
            return [
                "status": "success",
                "output": ConciseSerializer().serialize(tree),
            ]
        }
    }

    private func errorResponse(code: String, message: String) -> [String: Any] {
        ["status": "error", "error": code, "message": message]
    }

    private func writeResponse(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            let fallback = #"{"status":"error","error":"serialization_error","message":"Failed to serialize response"}"#
            print(fallback)
            return
        }
        print(json)
        fflush(stdout)
    }
}
