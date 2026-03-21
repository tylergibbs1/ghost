import Testing
@testable import GhostKit

@Suite("Element Resolution Tests")
struct ResolutionTests {

    // MARK: - Helpers

    private func makeNode(
        id: Int = 0,
        role: String,
        name: String? = nil,
        axIdentifier: String? = nil,
        children: [AXNode] = []
    ) -> AXNode {
        AXNode(id: id, role: role, name: name, axIdentifier: axIdentifier, children: children)
    }

    private func sampleTree() -> AXNode {
        let wifiToggle = makeNode(id: 5, role: "toggle", name: "Wi-Fi")
        let heading = makeNode(id: 4, role: "heading", name: "Wi-Fi")
        let content = makeNode(id: 3, role: "content", name: "content", children: [heading, wifiToggle])

        let item1 = makeNode(id: 6, role: "item", name: "Wi-Fi")
        let item2 = makeNode(id: 7, role: "item", name: "Network")
        let sidebar = makeNode(id: 2, role: "sidebar", name: "sidebar", children: [item1, item2])

        let window = makeNode(id: 1, role: "window", name: "System Settings", children: [sidebar, content])
        let root = makeNode(id: 0, role: "app", name: "System Settings", children: [window])
        return root
    }

    // MARK: - PathParser

    @Test("Parse role-only segments")
    func parseRoleSegments() {
        let parser = PathParser()
        let segments = parser.parse("sidebar > content")

        #expect(segments.count == 2)
        #expect(segments[0].role == "sidebar")
        #expect(segments[0].name == nil)
        #expect(segments[1].role == "content")
    }

    @Test("Parse name-only segments")
    func parseNameSegments() {
        let parser = PathParser()
        let segments = parser.parse("Wi-Fi")

        #expect(segments.count == 1)
        #expect(segments[0].name == "Wi-Fi")
        #expect(segments[0].role == nil)
    }

    @Test("Parse mixed role and name segments")
    func parseMixedSegments() {
        let parser = PathParser()
        let segments = parser.parse("content > toggle > Wi-Fi")

        #expect(segments.count == 3)
        #expect(segments[0].role == "content")
        #expect(segments[1].role == "toggle")
        #expect(segments[2].name == "Wi-Fi")
    }

    @Test("Parse empty string returns empty segments")
    func parseEmpty() {
        let parser = PathParser()
        let segments = parser.parse("")
        #expect(segments.isEmpty)
    }

    // MARK: - Exact Path Match

    @Test("Resolve exact path: sidebar > Wi-Fi")
    func resolveExactSidebar() throws {
        let resolver = ElementResolver()
        let tree = sampleTree()

        let node = try resolver.resolve(target: "sidebar > Wi-Fi", in: tree)
        #expect(node.role == "item")
        #expect(node.name == "Wi-Fi")
    }

    @Test("Resolve exact path: content > toggle > Wi-Fi")
    func resolveExactToggle() throws {
        let resolver = ElementResolver()
        let tree = sampleTree()

        let node = try resolver.resolve(target: "content > toggle", in: tree)
        #expect(node.role == "toggle")
        #expect(node.name == "Wi-Fi")
    }

    // MARK: - Role + Name Search (fallback)

    @Test("Resolve by role+name search when path doesn't match exactly")
    func resolveBySearch() throws {
        let resolver = ElementResolver()
        let tree = sampleTree()

        // "Network" only appears once, so role+name search should find it
        let node = try resolver.resolve(target: "Network", in: tree)
        #expect(node.name == "Network")
    }

    // MARK: - AXIdentifier Fallback

    @Test("Resolve by AXIdentifier when name search fails")
    func resolveByIdentifier() throws {
        let button = makeNode(id: 2, role: "button", name: "Localized Name", axIdentifier: "save-button")
        let root = makeNode(id: 0, role: "window", name: "Test", children: [button])

        let resolver = ElementResolver()
        let node = try resolver.resolve(target: "save-button", in: root)
        #expect(node.role == "button")
        #expect(node.axIdentifier == "save-button")
    }

    // MARK: - Error Cases

    @Test("Throw elementNotFound for missing target")
    func notFound() {
        let root = makeNode(id: 0, role: "window", name: "Test")
        let resolver = ElementResolver()

        #expect(throws: GhostError.self) {
            try resolver.resolve(target: "nonexistent", in: root)
        }
    }

    @Test("Throw invalidPath for empty target")
    func invalidPath() {
        let root = makeNode(id: 0, role: "window", name: "Test")
        let resolver = ElementResolver()

        #expect(throws: GhostError.self) {
            try resolver.resolve(target: "", in: root)
        }
    }
}
