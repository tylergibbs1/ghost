import Testing
@testable import GhostKit

@Suite("Pruning Pipeline Tests")
struct PruningTests {

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

    // MARK: - StripStructuralNoise

    @Test("Strip unnamed group nodes, splice children into parent")
    func stripUnnamedGroups() {
        let button = makeNode(id: 2, role: "button", name: "Save")
        let group = makeNode(id: 1, role: "group", children: [button])
        let root = makeNode(id: 0, role: "window", name: "Test", children: [group])

        let pass = StripStructuralNoise()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children.count == 1)
        #expect(result.children[0].role == "button")
        #expect(result.children[0].name == "Save")
    }

    @Test("Preserve named group nodes")
    func preserveNamedGroups() {
        let item = makeNode(id: 2, role: "item", name: "Wi-Fi")
        let sidebar = makeNode(id: 1, role: "group", name: "sidebar", children: [item])
        let root = makeNode(id: 0, role: "window", name: "Test", children: [sidebar])

        let pass = StripStructuralNoise()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children.count == 1)
        #expect(result.children[0].name == "sidebar")
        #expect(result.children[0].children.count == 1)
    }

    @Test("Strip nested noise nodes")
    func stripNestedNoise() {
        let text = makeNode(id: 3, role: "text", name: "Hello")
        let scrollArea = makeNode(id: 2, role: "scrollArea", children: [text])
        let group = makeNode(id: 1, role: "group", children: [scrollArea])
        let root = makeNode(id: 0, role: "window", name: "Test", children: [group])

        let pass = StripStructuralNoise()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children.count == 1)
        #expect(result.children[0].role == "text")
        #expect(result.children[0].name == "Hello")
    }

    // MARK: - CollapseSingleChild

    @Test("Collapse nameless parent with single child")
    func collapseSingleChild() {
        let button = makeNode(id: 2, role: "button", name: "OK")
        let wrapper = makeNode(id: 1, role: "tabGroup", children: [button])
        let root = makeNode(id: 0, role: "window", name: "Test", children: [wrapper])

        let pass = CollapseSingleChild()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children.count == 1)
        #expect(result.children[0].role == "button")
        #expect(result.children[0].name == "OK")
    }

    @Test("Preserve named parent even with single child")
    func preserveNamedParent() {
        let button = makeNode(id: 2, role: "button", name: "OK")
        let toolbar = makeNode(id: 1, role: "toolbar", name: "Actions", children: [button])
        let root = makeNode(id: 0, role: "window", name: "Test", children: [toolbar])

        let pass = CollapseSingleChild()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children.count == 1)
        #expect(result.children[0].name == "Actions")
        #expect(result.children[0].children.count == 1)
    }

    @Test("Never collapse window nodes")
    func neverCollapseWindow() {
        let content = makeNode(id: 1, role: "button", name: "OK")
        let root = makeNode(id: 0, role: "window", children: [content])

        let pass = CollapseSingleChild()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.role == "window")
        #expect(result.children.count == 1)
    }

    // MARK: - MergeAdjacentText

    @Test("Merge consecutive text nodes")
    func mergeAdjacentText() {
        let t1 = makeNode(id: 1, role: "text", name: "Hello")
        let t2 = makeNode(id: 2, role: "text", name: "World")
        let t3 = makeNode(id: 3, role: "text", name: "!")
        let root = makeNode(id: 0, role: "window", name: "Test", children: [t1, t2, t3])

        let pass = MergeAdjacentText()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children.count == 1)
        #expect(result.children[0].name == "Hello World !")
    }

    @Test("Don't merge text nodes separated by other elements")
    func dontMergeSeparatedText() {
        let t1 = makeNode(id: 1, role: "text", name: "Hello")
        let btn = makeNode(id: 2, role: "button", name: "Click")
        let t2 = makeNode(id: 3, role: "text", name: "World")
        let root = makeNode(id: 0, role: "window", name: "Test", children: [t1, btn, t2])

        let pass = MergeAdjacentText()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children.count == 3)
    }

    // MARK: - AnnotateState

    @Test("Annotate empty text field")
    func annotateEmptyTextField() {
        let field = makeNode(id: 1, role: "textfield", name: "Search")
        let root = makeNode(id: 0, role: "window", name: "Test", children: [field])

        let pass = AnnotateState()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children[0].value == "empty")
    }

    @Test("Preserve existing text field value")
    func preserveTextFieldValue() {
        let field = makeNode(id: 1, role: "textfield", name: "Search", value: "query")
        let root = makeNode(id: 0, role: "window", name: "Test", children: [field])

        let pass = AnnotateState()
        let result = pass.apply(to: root, context: PruningContext())

        #expect(result.children[0].value == "query")
    }

    // MARK: - TruncateLists

    @Test("Truncate long lists")
    func truncateLongList() {
        var items: [AXNode] = []
        for i in 0..<20 {
            items.append(makeNode(id: i + 1, role: "item", name: "Item \(i)"))
        }
        let root = makeNode(id: 0, role: "list", name: "Items", children: items)

        let pass = TruncateLists()
        let result = pass.apply(to: root, context: PruningContext(maxItems: 5))

        // 5 items + 1 summary
        #expect(result.children.count == 6)
        #expect(result.children.last?.name?.contains("15 more") == true)
    }

    @Test("Don't truncate short lists")
    func dontTruncateShortList() {
        let items = (0..<3).map { makeNode(id: $0 + 1, role: "item", name: "Item \($0)") }
        let root = makeNode(id: 0, role: "list", name: "Items", children: items)

        let pass = TruncateLists()
        let result = pass.apply(to: root, context: PruningContext(maxItems: 10))

        #expect(result.children.count == 3)
    }

    // MARK: - Full Pipeline

    @Test("Full pipeline produces clean output")
    func fullPipeline() {
        // Simulate a messy raw tree
        let button = makeNode(id: 5, role: "button", name: "Save")
        let innerGroup = makeNode(id: 4, role: "group", children: [button])
        let text1 = makeNode(id: 6, role: "text", name: "Status:")
        let text2 = makeNode(id: 7, role: "text", name: "Ready")
        let scrollArea = makeNode(id: 3, role: "scrollArea", children: [innerGroup, text1, text2])
        let group = makeNode(id: 2, role: "group", children: [scrollArea])
        let field = makeNode(id: 8, role: "textfield", name: "Search")
        let root = makeNode(id: 0, role: "window", name: "Test", children: [group, field])

        let pipeline = PruningPipeline()
        let result = pipeline.prune(root, context: PruningContext())

        // The messy nesting should be flattened
        // Button should be accessible, text merged, field annotated
        #expect(result.role == "window")
        #expect(result.name == "Test")

        // Find the button somewhere in the flattened tree
        func findButton(_ node: AXNode) -> AXNode? {
            if node.role == "button" && node.name == "Save" { return node }
            return node.children.compactMap { findButton($0) }.first
        }
        #expect(findButton(result) != nil)

        // Find the text field
        func findField(_ node: AXNode) -> AXNode? {
            if node.role == "textfield" { return node }
            return node.children.compactMap { findField($0) }.first
        }
        let field2 = findField(result)
        #expect(field2 != nil)
        #expect(field2?.value == "empty")
    }
}
