import Testing
@testable import GhostKit

@Suite("Snapshot Store Tests")
struct SnapshotTests {

    private func makeNode(
        id: Int = 0,
        role: String,
        name: String? = nil,
        value: String? = nil,
        children: [AXNode] = []
    ) -> AXNode {
        AXNode(id: id, role: role, name: name, value: value, children: children)
    }

    @Test("Capture and check identical tree returns match")
    func captureAndCheck() throws {
        let store = SnapshotStore()
        let tree = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "button", name: "OK"),
        ])

        store.capture(app: "TestApp", label: "before", tree: tree)
        let matches = try store.check(app: "TestApp", label: "before", currentTree: tree)
        #expect(matches)
    }

    @Test("Compare detects changes")
    func compareDetectsChanges() throws {
        let store = SnapshotStore()
        let before = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "toggle", name: "Wi-Fi", value: "on"),
        ])
        let after = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "toggle", name: "Wi-Fi", value: "off"),
        ])

        store.capture(app: "Settings", label: "initial", tree: before)
        let diff = try store.compare(app: "Settings", label: "initial", currentTree: after)
        #expect(!diff.isEmpty)
    }

    @Test("Check returns false for changed tree")
    func checkDetectsChange() throws {
        let store = SnapshotStore()
        let before = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "button", name: "OK"),
        ])
        let after = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "button", name: "Cancel"),
        ])

        store.capture(app: "TestApp", label: "snapshot1", tree: before)
        let matches = try store.check(app: "TestApp", label: "snapshot1", currentTree: after)
        #expect(!matches)
    }

    @Test("Missing snapshot throws error")
    func missingSnapshot() {
        let store = SnapshotStore()
        let tree = makeNode(role: "window", name: "Test")

        #expect(throws: GhostError.self) {
            try store.compare(app: "TestApp", label: "nonexistent", currentTree: tree)
        }
    }

    @Test("Labels are scoped per app")
    func labelsPerApp() {
        let store = SnapshotStore()
        let tree = makeNode(role: "window", name: "Test")

        store.capture(app: "AppA", label: "snap1", tree: tree)
        store.capture(app: "AppA", label: "snap2", tree: tree)
        store.capture(app: "AppB", label: "snap1", tree: tree)

        #expect(store.labels(for: "AppA").count == 2)
        #expect(store.labels(for: "AppB").count == 1)
    }

    @Test("Snapshot is a deep copy")
    func snapshotIsDeepCopy() throws {
        let store = SnapshotStore()
        let tree = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "toggle", name: "Wi-Fi", value: "on"),
        ])

        store.capture(app: "TestApp", label: "snap", tree: tree)

        // Mutate the original tree
        tree.children[0].value = "off"

        // Snapshot should still have "on"
        let matches = try store.check(app: "TestApp", label: "snap", currentTree: tree)
        #expect(!matches) // Should detect the change
    }

    @Test("Clear removes all snapshots")
    func clearAll() {
        let store = SnapshotStore()
        let tree = makeNode(role: "window", name: "Test")

        store.capture(app: "AppA", label: "snap1", tree: tree)
        store.capture(app: "AppB", label: "snap2", tree: tree)
        store.clear()

        #expect(store.labels(for: "AppA").isEmpty)
        #expect(store.labels(for: "AppB").isEmpty)
    }
}
