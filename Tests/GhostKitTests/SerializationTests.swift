import Testing
@testable import GhostKit
import Foundation

@Suite("Serialization Tests")
struct SerializationTests {

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

    // MARK: - Concise Serializer

    @Test("Concise format for simple tree")
    func conciseSimple() {
        let root = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "button", name: "Save"),
        ])

        let output = ConciseSerializer().serialize(root)
        #expect(output.contains("[window] Test"))
        #expect(output.contains("[button] Save"))
    }

    @Test("Concise format includes state annotations")
    func conciseWithState() {
        let toggle = makeNode(id: 1, role: "toggle", name: "Wi-Fi", value: "on")
        let root = makeNode(role: "window", name: "Settings", children: [toggle])

        let output = ConciseSerializer().serialize(root)
        #expect(output.contains("[toggle] Wi-Fi (on)"))
    }

    @Test("Concise format indentation")
    func conciseIndentation() {
        let button = makeNode(id: 2, role: "button", name: "OK")
        let toolbar = makeNode(id: 1, role: "toolbar", name: "Actions", children: [button])
        let root = makeNode(role: "window", name: "Test", children: [toolbar])

        let output = ConciseSerializer().serialize(root)
        let lines = output.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "[window] Test")
        #expect(lines[1] == "  [toolbar] Actions")
        #expect(lines[2] == "    [button] OK")
    }

    @Test("Concise format with multiple state flags")
    func conciseMultipleStates() {
        let item = makeNode(id: 1, role: "item", name: "Disabled Option", state: [.disabled, .selected])
        let root = makeNode(role: "list", children: [item])

        let output = ConciseSerializer().serialize(root)
        #expect(output.contains("(disabled, selected)"))
    }

    // MARK: - Detailed Serializer

    @Test("Detailed format produces valid JSON")
    func detailedValidJSON() {
        let root = makeNode(role: "window", name: "Test", children: [
            makeNode(id: 1, role: "button", name: "Save"),
        ])

        let json = DetailedSerializer().serialize(root)
        let data = json.data(using: .utf8)!
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["role"] as? String == "window")
        #expect(parsed["name"] as? String == "Test")
        #expect((parsed["children"] as? [[String: Any]])?.count == 1)
    }

    @Test("Detailed format includes actions")
    func detailedIncludesActions() {
        let button = AXNode(
            id: 1,
            role: "button",
            name: "Save",
            actions: ["press"]
        )
        let root = makeNode(role: "window", name: "Test", children: [button])

        let json = DetailedSerializer().serialize(root)
        #expect(json.contains("\"press\""))
    }

    @Test("Detailed format includes state as dict")
    func detailedStateDict() {
        let item = makeNode(id: 1, role: "item", name: "Wi-Fi", state: [.selected])
        let root = makeNode(role: "list", name: "Sidebar", children: [item])

        let dict = DetailedSerializer().serializeToDict(root)
        let children = dict["children"] as! [[String: Any]]
        let stateDict = children[0]["state"] as! [String: Bool]
        #expect(stateDict["selected"] == true)
    }
}
