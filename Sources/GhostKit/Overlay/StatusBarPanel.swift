import AppKit
import Foundation

/// Floating status bar showing a running log of Ghost actions.
/// Styled to match macOS system panels (screenshot toolbar, AirDrop indicator).
class StatusBarPanel: NSPanel {
    private let stackView: NSStackView
    private var entryViews: [NSTextField] = []
    private let titleLabel: NSTextField
    private let maxEntries = DesignTokens.statusBarMaxEntries

    init() {
        let dt = DesignTokens.self
        let width = dt.statusBarWidth
        let height = dt.statusBarHeight

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height - dt.statusBarTopInset

        stackView = NSStackView()
        titleLabel = NSTextField(labelWithString: "")

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        isMovableByWindowBackground = true

        setupUI()
    }

    private func setupUI() {
        let dt = DesignTokens.self

        // Vibrancy container (matches macOS HUD style)
        let blur = NSVisualEffectView(frame: contentView!.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = dt.panelCornerRadius
        blur.layer?.masksToBounds = true

        // Title row: icon + "Ghost"
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 6
        titleRow.alignment = .centerY
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        // SF Symbol icon (or fallback emoji)
        let iconView = makeIcon()
        titleRow.addArrangedSubview(iconView)

        titleLabel.stringValue = "Ghost"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleRow.addArrangedSubview(titleLabel)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Log entries stack
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Outer stack
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 6
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        outerStack.addArrangedSubview(titleRow)
        outerStack.addArrangedSubview(separator)
        outerStack.addArrangedSubview(stackView)

        blur.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: blur.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            outerStack.bottomAnchor.constraint(lessThanOrEqualTo: blur.bottomAnchor),
            separator.widthAnchor.constraint(equalTo: outerStack.widthAnchor, constant: -28),
        ])

        contentView = blur
    }

    private func makeIcon() -> NSView {
        // Try SF Symbol first (macOS 11+), fall back to text
        if let image = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "Ghost") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            let imageView = NSImageView(image: image.withSymbolConfiguration(config) ?? image)
            imageView.contentTintColor = .controlAccentColor
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            return imageView
        }
        let fallback = NSTextField(labelWithString: "👻")
        fallback.font = .systemFont(ofSize: 12)
        return fallback
    }

    func addEntry(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Create a styled entry
            let entry = NSTextField(labelWithString: "")
            let attributed = NSMutableAttributedString()

            // Dimmed bullet
            let bulletAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            attributed.append(NSAttributedString(string: "● ", attributes: bulletAttrs))

            // Entry text
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            attributed.append(NSAttributedString(string: text, attributes: textAttrs))

            entry.attributedStringValue = attributed
            entry.lineBreakMode = .byTruncatingTail
            entry.maximumNumberOfLines = 1

            // Animate in
            entry.alphaValue = 0
            self.stackView.addArrangedSubview(entry)
            self.entryViews.append(entry)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                entry.animator().alphaValue = 1
            }

            // Remove old entries
            while self.entryViews.count > self.maxEntries {
                let old = self.entryViews.removeFirst()
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    old.animator().alphaValue = 0
                }, completionHandler: {
                    old.removeFromSuperview()
                })
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entryViews.forEach { $0.removeFromSuperview() }
            self?.entryViews.removeAll()
        }
    }
}
