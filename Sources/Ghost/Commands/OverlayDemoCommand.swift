import AppKit
import ArgumentParser
import Foundation
import GhostKit

struct OverlayDemoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overlay-demo",
        abstract: "Demo the visual overlay system."
    )

    @Option(name: .long, help: "Animation speed: fast, normal, slow.")
    var speed: String = "normal"

    @Option(name: .long, help: "Duration to show overlay in seconds. Default: 5.")
    var duration: Int = 5

    func run() async throws {
        let animSpeed = AnimationSpeed(rawValue: speed) ?? .normal
        let overlay = OverlayController.shared
        overlay.start(config: OverlayConfig(enabled: true, statusBar: true, animationSpeed: animSpeed))

        // Give windows time to appear
        try await Task.sleep(nanoseconds: 200_000_000)

        print("Overlay demo started. Showing actions for \(duration) seconds...")

        // Read the frontmost app's tree to get real element positions
        let appResolver = AppResolver()
        let apps = appResolver.listRunning().filter { $0.isActive }

        if let frontApp = apps.first {
            let appName = frontApp.localizedName ?? "Unknown"
            print("Reading \(appName) tree...")

            var reader = AXTreeReader()
            if let tree = try? reader.readTree(pid: frontApp.processIdentifier) {
                let pipeline = PruningPipeline()
                let pruned = pipeline.prune(tree)

                // Collect elements with frames
                var elements: [AXNode] = []
                collectWithFrames(pruned, into: &elements)

                if elements.isEmpty {
                    print("No elements with frames found. Showing demo at fixed positions.")
                    showFixedDemo(overlay, animSpeed: animSpeed)
                } else {
                    print("Found \(elements.count) elements with frames. Highlighting...")
                    try await showRealDemo(overlay, elements: elements, animSpeed: animSpeed)
                }
            } else {
                print("Could not read tree. Showing demo at fixed positions.")
                showFixedDemo(overlay, animSpeed: animSpeed)
            }
        } else {
            showFixedDemo(overlay, animSpeed: animSpeed)
        }

        // Keep overlay visible
        print("Overlay visible for \(duration) seconds...")
        try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)

        overlay.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        print("Overlay demo complete.")
    }

    private func showFixedDemo(_ overlay: OverlayController, animSpeed: AnimationSpeed) {
        // Show demo highlights at fixed screen positions
        overlay.showObserve(
            frame: CGRect(x: 50, y: 50, width: 300, height: 200),
            label: "Demo: observe"
        )
        overlay.showPress(
            frame: CGRect(x: 400, y: 100, width: 120, height: 30),
            label: "[button] Save"
        )
        overlay.showType(
            frame: CGRect(x: 400, y: 160, width: 200, height: 30),
            label: "[textfield] Search",
            text: "hello world"
        )
        overlay.showSelect(
            frame: CGRect(x: 50, y: 300, width: 150, height: 25),
            label: "[item] Network"
        )
        overlay.showKey(
            frame: CGRect(x: 250, y: 300, width: 100, height: 30),
            shortcut: "cmd+s"
        )
    }

    private func showRealDemo(_ overlay: OverlayController, elements: [AXNode], animSpeed: AnimationSpeed) async throws {
        let actions = ["observe", "press", "type", "select", "key"]
        let delay = UInt64(animSpeed.duration * 1_500_000_000)

        for (i, element) in elements.prefix(8).enumerated() {
            let action = actions[i % actions.count]
            overlay.highlightNode(element, action: action)
            try await Task.sleep(nanoseconds: delay)
        }
    }

    private func collectWithFrames(_ node: AXNode, into results: inout [AXNode]) {
        if let frame = node.frame, frame.width > 10, frame.height > 10 {
            results.append(node)
        }
        for child in node.children {
            collectWithFrames(child, into: &results)
        }
    }
}
