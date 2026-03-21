import ApplicationServices
import AppKit
import Foundation

/// Reads the macOS accessibility tree for a given application, producing an AXNode tree.
public struct AXTreeReader {
    private var idCounter: Int = 0

    public init() {}

    // MARK: - Public API

    /// Read the full accessibility tree for an application by PID.
    public mutating func readTree(pid: pid_t) throws -> AXNode {
        let appElement = AXUIElementCreateApplication(pid)

        guard axIsProcessTrusted() else {
            throw GhostError.axPermissionDenied
        }

        return try readElement(appElement, depth: 0)
    }

    /// Read a summary of all running GUI applications.
    public func readDesktop() -> AXNode {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        var counter = 0
        let desktopNode = AXNode(id: counter, role: "desktop", name: nil)
        counter += 1

        for app in apps {
            let appNode = AXNode(
                id: counter,
                role: "app",
                name: app.localizedName,
                state: app.isActive ? [.focused] : []
            )
            counter += 1

            // Read window titles without full tree traversal
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if let windowTitles = readWindowTitles(from: appElement) {
                for title in windowTitles {
                    let windowNode = AXNode(id: counter, role: "window", name: title)
                    counter += 1
                    appNode.children.append(windowNode)
                }
            }

            desktopNode.children.append(appNode)
        }

        // Add menubar
        if let menubar = readMenuBar(&counter) {
            desktopNode.children.append(menubar)
        }

        return desktopNode
    }

    // MARK: - Private

    private mutating func readElement(_ element: AXUIElement, depth: Int) throws -> AXNode {
        // Prevent runaway recursion on deep/circular trees
        guard depth < 50 else {
            let node = AXNode(id: nextId(), role: "truncated", name: "max depth reached")
            return node
        }

        let role = mapRole(axRole(of: element))
        let name = axStringAttribute(of: element, attribute: kAXTitleAttribute as CFString)
            ?? axStringAttribute(of: element, attribute: kAXDescriptionAttribute as CFString)
        let value = readValue(element, role: role)
        let identifier = axStringAttribute(of: element, attribute: kAXIdentifierAttribute as CFString)
        let actions = readActions(element)
        let frame = readFrame(element)
        let state = readState(element)

        let node = AXNode(
            id: nextId(),
            role: role,
            name: name,
            value: value,
            state: state,
            actions: actions,
            axIdentifier: identifier,
            frame: frame,
            elementRef: element
        )

        // Read children
        if let children = axArrayAttribute(of: element, attribute: kAXChildrenAttribute as CFString) {
            for child in children {
                let childElement = child as! AXUIElement
                // Skip hidden elements
                if isHidden(childElement) { continue }
                do {
                    let childNode = try readElement(childElement, depth: depth + 1)
                    node.children.append(childNode)
                } catch {
                    // Skip unreadable children
                    continue
                }
            }
        }

        return node
    }

    private mutating func nextId() -> Int {
        let id = idCounter
        idCounter += 1
        return id
    }

    // MARK: - AX Attribute Helpers

    private func axRole(of element: AXUIElement) -> String {
        axStringAttribute(of: element, attribute: kAXRoleAttribute as CFString) ?? "unknown"
    }

    private func axStringAttribute(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    private func axBoolAttribute(of element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        if let num = value as? NSNumber {
            return num.boolValue
        }
        return nil
    }

    private func axArrayAttribute(of element: AXUIElement, attribute: CFString) -> [AnyObject]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let arr = value as? [AnyObject] else { return nil }
        return arr
    }

    private func readValue(_ element: AXUIElement, role: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else { return nil }

        if let str = value as? String {
            return str.isEmpty ? nil : str
        }
        if let num = value as? NSNumber {
            // For toggles/checkboxes, map to on/off
            if role == "toggle" || role == "checkbox" {
                return num.boolValue ? "on" : "off"
            }
            return num.stringValue
        }
        return nil
    }

    private func readActions(_ element: AXUIElement) -> [String] {
        var actionNames: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNames)
        guard result == .success, let names = actionNames as? [String] else { return [] }
        return names.map { mapAction($0) }
    }

    private func readFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: point, size: size)
    }

    private func readState(_ element: AXUIElement) -> Set<NodeState> {
        var state = Set<NodeState>()

        if axBoolAttribute(of: element, attribute: kAXSelectedAttribute as CFString) == true {
            state.insert(.selected)
        }
        if axBoolAttribute(of: element, attribute: kAXEnabledAttribute as CFString) == false {
            state.insert(.disabled)
        }
        if axBoolAttribute(of: element, attribute: kAXExpandedAttribute as CFString) == true {
            state.insert(.expanded)
        }
        if axBoolAttribute(of: element, attribute: kAXFocusedAttribute as CFString) == true {
            state.insert(.focused)
        }
        if axBoolAttribute(of: element, attribute: "AXRequired" as CFString) == true {
            state.insert(.required)
        }

        return state
    }

    private func isHidden(_ element: AXUIElement) -> Bool {
        // Check if the element or its window is hidden
        if axBoolAttribute(of: element, attribute: "AXHidden" as CFString) == true {
            return true
        }
        return false
    }

    private func readWindowTitles(from appElement: AXUIElement) -> [String]? {
        guard let windows = axArrayAttribute(of: appElement, attribute: kAXWindowsAttribute as CFString) else {
            return nil
        }
        return windows.compactMap { window in
            axStringAttribute(of: window as! AXUIElement, attribute: kAXTitleAttribute as CFString)
        }
    }

    private func readMenuBar(_ counter: inout Int) -> AXNode? {
        // Read the system-wide menubar element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else {
            return nil
        }

        let appElement = focusedApp as! AXUIElement
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success else {
            return nil
        }

        let menuBar = menuBarRef as! AXUIElement
        let node = AXNode(id: counter, role: "menubar")
        counter += 1

        if let items = axArrayAttribute(of: menuBar, attribute: kAXChildrenAttribute as CFString) {
            for item in items {
                let itemElement = item as! AXUIElement
                let title = axStringAttribute(of: itemElement, attribute: kAXTitleAttribute as CFString)
                let menuNode = AXNode(id: counter, role: "menu", name: title)
                counter += 1
                node.children.append(menuNode)
            }
        }

        return node
    }

    // MARK: - Role Mapping

    /// Maps raw AX role strings to Ghost's simplified role vocabulary.
    private func mapRole(_ axRole: String) -> String {
        switch axRole {
        case "AXApplication": return "app"
        case "AXWindow": return "window"
        case "AXSheet": return "sheet"
        case "AXDialog": return "dialog"
        case "AXButton": return "button"
        case "AXRadioButton": return "radio"
        case "AXCheckBox": return "toggle"
        case "AXTextField", "AXTextArea", "AXSecureTextField": return "textfield"
        case "AXStaticText": return "text"
        case "AXHeading": return "heading"
        case "AXLink": return "link"
        case "AXImage": return "image"
        case "AXList": return "list"
        case "AXTable": return "table"
        case "AXOutline": return "outline"
        case "AXRow": return "row"
        case "AXColumn": return "column"
        case "AXCell": return "cell"
        case "AXGroup": return "group"
        case "AXScrollArea": return "scrollArea"
        case "AXSplitGroup": return "splitGroup"
        case "AXLayoutArea": return "layoutArea"
        case "AXTabGroup": return "tabGroup"
        case "AXTab": return "tab"
        case "AXToolbar": return "toolbar"
        case "AXMenuBar": return "menubar"
        case "AXMenu": return "menu"
        case "AXMenuItem": return "menuItem"
        case "AXPopUpButton": return "dropdown"
        case "AXComboBox": return "combobox"
        case "AXSlider": return "slider"
        case "AXProgressIndicator": return "progress"
        case "AXValueIndicator": return "indicator"
        case "AXDisclosureTriangle": return "disclosure"
        case "AXBrowser": return "browser"
        case "AXSplitter": return "splitter"
        case "AXColorWell": return "colorWell"
        case "AXGrowArea": return "growArea"
        case "AXRulerMarker": return "ruler"
        case "AXSearchField": return "search"
        case "AXRelevanceIndicator": return "relevance"
        default: return axRole.replacingOccurrences(of: "AX", with: "").lowercased()
        }
    }

    /// Maps raw AX action names to Ghost's simplified action vocabulary.
    private func mapAction(_ axAction: String) -> String {
        switch axAction {
        case "AXPress": return "press"
        case "AXConfirm": return "confirm"
        case "AXCancel": return "cancel"
        case "AXRaise": return "raise"
        case "AXShowMenu": return "showMenu"
        case "AXIncrement": return "increment"
        case "AXDecrement": return "decrement"
        case "AXPick": return "pick"
        default: return axAction.replacingOccurrences(of: "AX", with: "").lowercased()
        }
    }

    // MARK: - Permission Check

    private func axIsProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
