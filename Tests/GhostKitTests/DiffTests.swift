import Testing
@testable import GhostKit

@Suite("Tree Differ Tests")
struct DiffTests {

    // MARK: - Helpers

    private func makeNode(
        id: Int = 0,
        role: String,
        name: String? = nil,
        value: String? = nil,
        state: Set<NodeState> = [],
        children: [AXNode] = []
    ) -> AXNode {
        AXNode(id: id, role: role, name: name, value: value, state: state, children: children)
    }

    // MARK: - No Changes

    @Test("Identical trees produce no diff")
    func noDiff() {
        let before = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "button", name: "OK"),
        ])
        let after = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "button", name: "OK"),
        ])

        let differ = TreeDiffer()
        let diff = differ.diff(before: before, after: after)
        #expect(diff.isEmpty)
    }

    // MARK: - Value Changes

    @Test("Detect value change on toggle")
    func valueChange() {
        let before = makeNode(role: "window", name: "Settings", children: [
            makeNode(id: 1, role: "toggle", name: "Wi-Fi", value: "on"),
        ])
        let after = makeNode(role: "window", name: "Settings", children: [
            makeNode(id: 1, role: "toggle", name: "Wi-Fi", value: "off"),
        ])

        let differ = TreeDiffer()
        let diff = differ.diff(before: before, after: after)

        #expect(diff.count == 1)
        if case .changed(_, let field, let from, let to) = diff[0] {
            #expect(field == "value")
            #expect(from == "on")
            #expect(to == "off")
        } else {
            Issue.record("Expected changed diff entry")
        }
    }

    // MARK: - State Changes

    @Test("Detect state change: selected added")
    func stateAdded() {
        let before = makeNode(role: "item", name: "Network")
        let after = makeNode(role: "item", name: "Network", state: [.selected])

        let differ = TreeDiffer()
        let diff = differ.diff(before: before, after: after)

        #expect(diff.count == 1)
        if case .changed(_, let field, _, _) = diff[0] {
            #expect(field == "selected")
        } else {
            Issue.record("Expected state change diff entry")
        }
    }

    // MARK: - Child Added/Removed

    @Test("Detect added child")
    func childAdded() {
        let before = makeNode(role: "list", name: "Items", children: [
            makeNode(id: 1, role: "item", name: "A"),
        ])
        let after = makeNode(role: "list", name: "Items", children: [
            makeNode(id: 1, role: "item", name: "A"),
            makeNode(id: 2, role: "item", name: "B"),
        ])

        let differ = TreeDiffer()
        let diff = differ.diff(before: before, after: after)

        let added = diff.filter { $0.type == "added" }
        #expect(added.count == 1)
    }

    @Test("Detect removed child")
    func childRemoved() {
        let before = makeNode(role: "list", name: "Items", children: [
            makeNode(id: 1, role: "item", name: "A"),
            makeNode(id: 2, role: "item", name: "B"),
        ])
        let after = makeNode(role: "list", name: "Items", children: [
            makeNode(id: 1, role: "item", name: "A"),
        ])

        let differ = TreeDiffer()
        let diff = differ.diff(before: before, after: after)

        let removed = diff.filter { $0.type == "removed" }
        #expect(removed.count == 1)
    }

    // MARK: - Complex Diff

    @Test("Detect multiple changes in a realistic scenario")
    func complexDiff() {
        let before = makeNode(role: "window", name: "Settings", children: [
            makeNode(id: 1, role: "sidebar", name: "sidebar", children: [
                makeNode(id: 2, role: "item", name: "Wi-Fi", state: [.selected]),
                makeNode(id: 3, role: "item", name: "Network"),
            ]),
            makeNode(id: 4, role: "content", name: "content", children: [
                makeNode(id: 5, role: "heading", name: "Wi-Fi"),
                makeNode(id: 6, role: "toggle", name: "Wi-Fi", value: "on"),
            ]),
        ])

        let after = makeNode(role: "window", name: "Settings", children: [
            makeNode(id: 1, role: "sidebar", name: "sidebar", children: [
                makeNode(id: 2, role: "item", name: "Wi-Fi"),
                makeNode(id: 3, role: "item", name: "Network", state: [.selected]),
            ]),
            makeNode(id: 4, role: "content", name: "content", children: [
                makeNode(id: 5, role: "heading", name: "Network"),
                makeNode(id: 7, role: "text", name: "VPN: Not Connected"),
            ]),
        ])

        let differ = TreeDiffer()
        let diff = differ.diff(before: before, after: after)

        // Should detect:
        // - Wi-Fi sidebar item: selected removed
        // - Network sidebar item: selected added
        // - Heading changed from Wi-Fi to Network (different name = removed + added)
        // - Toggle removed
        // - Text "VPN: Not Connected" added
        #expect(diff.count >= 4)
    }
}
