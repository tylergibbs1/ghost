import AppKit
import Foundation

/// Orchestrates the visual overlay system.
/// Call from any thread — all UI work is dispatched to the main thread.
public final class OverlayController: @unchecked Sendable {
    public static let shared = OverlayController()

    public var config: OverlayConfig = OverlayConfig()

    private var overlayWindows: [OverlayWindow] = []
    private var statusBar: StatusBarPanel?
    private var isStarted = false

    private init() {}

    // MARK: - Lifecycle

    public func start(config: OverlayConfig = OverlayConfig(enabled: true)) {
        self.config = config
        guard config.enabled else { return }

        DispatchQueue.main.async { [weak self] in
            self?.startOnMain()
        }
    }

    private func startOnMain() {
        guard !isStarted else { return }
        isStarted = true

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        for screen in NSScreen.screens {
            let window = OverlayWindow.create(for: screen)
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        if config.statusBar {
            statusBar = StatusBarPanel()
            statusBar?.orderFrontRegardless()
        }
    }

    public func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for window in self.overlayWindows {
                if let view = window.contentView as? OverlayContentView {
                    view.removeAllHighlights(animationSpeed: self.config.animationSpeed)
                }
            }
            // Close windows after animations finish
            let delay = self.config.animationSpeed.duration + 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.overlayWindows.forEach { $0.close() }
                self?.overlayWindows.removeAll()
                self?.statusBar?.close()
                self?.statusBar = nil
                self?.isStarted = false
            }
        }
    }

    // MARK: - Core highlight

    /// Add an animated highlight at a screen position. Returns its ID.
    @discardableResult
    private func addHighlight(
        frame: CGRect,
        color: OverlayColor,
        label: String?,
        dashed: Bool = false,
        animationType: HighlightItem.AnimationType = .fade
    ) -> String {
        guard config.enabled else { return "" }

        let id = UUID().uuidString
        let screenFrame = convertToScreenCoordinates(frame)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let window = self.overlayWindows.first(where: { $0.frame.contains(screenFrame.origin) })
                ?? self.overlayWindows.first
            guard let window = window, let view = window.contentView as? OverlayContentView else { return }

            let localFrame = NSRect(
                x: screenFrame.origin.x - window.frame.origin.x,
                y: screenFrame.origin.y - window.frame.origin.y,
                width: screenFrame.width,
                height: screenFrame.height
            )
            let item = HighlightItem(
                frame: localFrame,
                color: color,
                label: label,
                dashed: dashed,
                animationType: animationType,
                id: id
            )
            view.addHighlight(item, animationSpeed: self.config.animationSpeed)
        }

        return id
    }

    /// Fade out and remove a highlight by ID.
    private func removeHighlightAnimated(id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for window in self.overlayWindows {
                if let view = window.contentView as? OverlayContentView {
                    view.removeHighlight(id: id, animationSpeed: self.config.animationSpeed)
                }
            }
        }
    }

    /// Schedule a highlight for auto-removal after a delay.
    private func autoRemove(id: String, after holdTime: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) { [weak self] in
            self?.removeHighlightAnimated(id: id)
        }
    }

    // MARK: - Action-specific animations

    /// Observe: subtle gray pulse.
    public func showObserve(frame: CGRect, label: String) {
        guard config.enabled else { return }
        let id = addHighlight(frame: frame, color: .observe, label: label)
        logAction("observe \(label)")
        autoRemove(id: id, after: config.animationSpeed.duration * DesignTokens.observeHold)
    }

    /// Press: accent-color highlight with spring scale.
    public func showPress(frame: CGRect, label: String) {
        guard config.enabled else { return }
        let id = addHighlight(frame: frame, color: .press, label: label, animationType: .press)
        logAction("press \(label)")
        autoRemove(id: id, after: config.animationSpeed.duration * DesignTokens.pressHold)
    }

    /// Type: green highlight with cursor blink.
    public func showType(frame: CGRect, label: String, text: String) {
        guard config.enabled else { return }
        let id = addHighlight(frame: frame, color: .type, label: "\(label)  \u{2190}  \"\(text)\"", animationType: .type)
        logAction("type \"\(text)\" \u{2192} \(label)")
        autoRemove(id: id, after: config.animationSpeed.duration * DesignTokens.typeHold)
    }

    /// Select: purple highlight.
    public func showSelect(frame: CGRect, label: String) {
        guard config.enabled else { return }
        let id = addHighlight(frame: frame, color: .select, label: label)
        logAction("select \(label)")
        autoRemove(id: id, after: config.animationSpeed.duration * DesignTokens.selectHold)
    }

    /// Key: orange highlight with shortcut label.
    public func showKey(frame: CGRect, shortcut: String) {
        guard config.enabled else { return }
        let id = addHighlight(frame: frame, color: .key, label: shortcut)
        logAction("key \(shortcut)")
        autoRemove(id: id, after: config.animationSpeed.duration * DesignTokens.keyHold)
    }

    /// Navigate: log only.
    public func showNavigate(appName: String) {
        guard config.enabled else { return }
        logAction("navigate \u{2192} \(appName)")
    }

    /// Denied: red with shake.
    public func showDenied(frame: CGRect, label: String) {
        guard config.enabled else { return }
        let id = addHighlight(frame: frame, color: .denied, label: label, animationType: .denied)
        logAction("denied: \(label)")
        autoRemove(id: id, after: config.animationSpeed.duration * DesignTokens.deniedHold)
    }

    /// Plan preview: dashed borders.
    public func showPlanPreview(frame: CGRect, action: String, label: String) {
        guard config.enabled else { return }
        let id = addHighlight(frame: frame, color: OverlayColor.forAction(action), label: "\(action): \(label)", dashed: true)
        logAction("plan: would \(action) \(label)")
        autoRemove(id: id, after: config.animationSpeed.duration * DesignTokens.planHold)
    }

    // MARK: - Diff Display

    public func showDiff(_ entries: [DiffEntry], tree: AXNode) {
        guard config.enabled else { return }
        for entry in entries {
            logAction("diff: \(entry.description)")
        }
    }

    // MARK: - Status Bar

    public func logAction(_ text: String) {
        guard config.enabled, config.statusBar else { return }
        DispatchQueue.main.async { [weak self] in
            self?.statusBar?.addEntry(text)
        }
    }

    // MARK: - Coordinate Conversion

    private func convertToScreenCoordinates(_ axFrame: CGRect) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: axFrame.origin, size: axFrame.size)
        }
        let screenHeight = screen.frame.height
        return NSRect(
            x: axFrame.origin.x,
            y: screenHeight - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )
    }

    // MARK: - AXNode convenience

    public func highlightNode(_ node: AXNode, action: String) {
        guard let frame = node.frame else { return }
        let label = node.displayLabel

        switch action {
        case "observe":  showObserve(frame: frame, label: label)
        case "press":    showPress(frame: frame, label: label)
        case "type":     showType(frame: frame, label: label, text: node.value ?? "")
        case "select":   showSelect(frame: frame, label: label)
        case "key":      showKey(frame: frame, shortcut: node.value ?? "")
        default:         showObserve(frame: frame, label: label)
        }
    }
}
