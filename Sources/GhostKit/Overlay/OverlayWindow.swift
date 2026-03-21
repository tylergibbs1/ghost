import AppKit
import QuartzCore
import Foundation

// MARK: - Overlay Window

/// Transparent, click-through window that covers a screen.
class OverlayWindow: NSWindow {
    static func create(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = OverlayContentView(frame: screen.frame)
        window.contentView = view

        return window
    }
}

// MARK: - Content View (layer-backed)

/// Each highlight is a sublayer tree with independent Core Animation.
class OverlayContentView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Add

    func addHighlight(_ item: HighlightItem, animationSpeed: AnimationSpeed) {
        let dt = DesignTokens.self
        let rect = item.frame.insetBy(dx: dt.highlightInset, dy: dt.highlightInset)

        let container = CALayer()
        container.name = item.id
        container.frame = rect
        container.opacity = 0
        container.cornerRadius = dt.highlightCornerRadius

        // Shadow (soft Apple-style)
        container.shadowColor = item.borderColor.cgColor
        container.shadowOpacity = 0.25
        container.shadowRadius = 8
        container.shadowOffset = CGSize(width: 0, height: -2)

        // Fill shape
        let bounds = CGRect(origin: .zero, size: rect.size)
        let fill = CAShapeLayer()
        fill.path = CGPath(roundedRect: bounds,
                           cornerWidth: dt.highlightCornerRadius,
                           cornerHeight: dt.highlightCornerRadius,
                           transform: nil)
        fill.fillColor = item.fillColor.cgColor
        container.addSublayer(fill)

        // Border shape
        let border = CAShapeLayer()
        border.path = fill.path
        border.fillColor = nil
        border.strokeColor = item.borderColor.cgColor
        border.lineWidth = item.dashed ? dt.highlightDashedWidth : dt.highlightBorderWidth
        if item.dashed {
            border.lineDashPattern = dt.dashPattern
        }
        container.addSublayer(border)

        layer?.addSublayer(container)

        // Label
        if let label = item.label {
            let labelLayer = buildLabel(text: label, color: item.color, anchorRect: rect)
            labelLayer.name = "\(item.id)-label"
            labelLayer.opacity = 0
            layer?.addSublayer(labelLayer)
            animateFadeIn(labelLayer, speed: animationSpeed, delay: animationSpeed.duration * 0.15)
        }

        // Entrance animation
        switch item.animationType {
        case .press:
            animateSpringIn(container, speed: animationSpeed)
        default:
            animateFadeIn(container, speed: animationSpeed)
        }

        // Action-specific ongoing animations
        switch item.animationType {
        case .press:
            animateRipple(container, speed: animationSpeed)
        case .type:
            animateCursorBlink(border)
        case .denied:
            animateShake(container)
        default:
            break
        }
    }

    // MARK: - Remove

    func removeHighlight(id: String, animationSpeed: AnimationSpeed) {
        guard let sublayers = layer?.sublayers else { return }
        let targets = sublayers.filter { $0.name == id || $0.name == "\(id)-label" }
        for target in targets {
            animateFadeOut(target, speed: animationSpeed)
        }
    }

    func removeAllHighlights(animationSpeed: AnimationSpeed) {
        guard let sublayers = layer?.sublayers else { return }
        for sub in sublayers {
            animateFadeOut(sub, speed: animationSpeed)
        }
    }

    // MARK: - Entrance Animations

    private func animateFadeIn(_ layer: CALayer, speed: AnimationSpeed, delay: CFTimeInterval = 0) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0
        anim.toValue = 1
        anim.duration = speed.duration * 0.7
        anim.beginTime = CACurrentMediaTime() + delay
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "fadeIn")
    }

    /// Spring scale-up entrance (for press actions).
    private func animateSpringIn(_ layer: CALayer, speed: AnimationSpeed) {
        // Start slightly scaled down + transparent
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        opacity.duration = speed.duration * 0.5
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false

        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.0
        scale.damping = DesignTokens.springDamping * 10
        scale.stiffness = DesignTokens.springStiffness
        scale.mass = DesignTokens.springMass
        scale.initialVelocity = DesignTokens.springInitialVelocity
        scale.duration = speed.springDuration
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false

        layer.add(opacity, forKey: "springFadeIn")
        layer.add(scale, forKey: "springScale")
    }

    // MARK: - Ongoing Animations

    /// Subtle scale pulse for press.
    private func animateRipple(_ layer: CALayer, speed: AnimationSpeed) {
        let ripple = CAKeyframeAnimation(keyPath: "transform.scale")
        ripple.values = [1.0, DesignTokens.pressScalePeak, 1.0]
        ripple.keyTimes = [0, 0.35, 1.0]
        ripple.duration = speed.duration * 1.2
        ripple.beginTime = CACurrentMediaTime() + speed.duration * 0.5
        ripple.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(ripple, forKey: "ripple")
    }

    /// Blinking border for type/text input.
    private func animateCursorBlink(_ borderLayer: CAShapeLayer) {
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1.0
        blink.toValue = DesignTokens.cursorBlinkMinAlpha
        blink.duration = DesignTokens.cursorBlinkDuration
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        borderLayer.add(blink, forKey: "cursorBlink")
    }

    /// Horizontal shake for denied actions.
    private func animateShake(_ layer: CALayer) {
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        let x = layer.position.x
        shake.values = [x, x - 6, x + 5, x - 4, x + 3, x - 2, x]
        shake.keyTimes = [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]
        shake.duration = 0.45
        shake.beginTime = CACurrentMediaTime() + 0.1
        layer.add(shake, forKey: "shake")
    }

    // MARK: - Exit Animation

    private func animateFadeOut(_ layer: CALayer, speed: AnimationSpeed) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? 1.0
        anim.toValue = 0
        anim.duration = speed.fadeOutDuration
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "fadeOut")

        DispatchQueue.main.asyncAfter(deadline: .now() + speed.fadeOutDuration + 0.05) {
            layer.removeFromSuperlayer()
        }
    }

    // MARK: - Label Builder

    private func buildLabel(text: String, color: OverlayColor, anchorRect: CGRect) -> CALayer {
        let dt = DesignTokens.self
        let font = dt.labelFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attrs)

        let pillW = textSize.width + dt.labelPadding * 2
        let pillH = textSize.height + dt.labelVerticalPadding * 2

        let container = CALayer()
        container.frame = CGRect(
            x: anchorRect.minX,
            y: anchorRect.maxY + dt.labelOffset,
            width: pillW,
            height: pillH
        )

        // Pill background — shadow for depth
        let bg = CAShapeLayer()
        let pillBounds = CGRect(origin: .zero, size: container.bounds.size)
        bg.path = CGPath(roundedRect: pillBounds,
                         cornerWidth: dt.labelCornerRadius,
                         cornerHeight: dt.labelCornerRadius,
                         transform: nil)
        bg.fillColor = color.labelBackground.cgColor
        container.addSublayer(bg)

        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.3
        container.shadowRadius = 6
        container.shadowOffset = CGSize(width: 0, height: -1)

        // Text
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = font
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer.frame = CGRect(
            x: dt.labelPadding,
            y: dt.labelVerticalPadding - 1,
            width: textSize.width,
            height: textSize.height
        )
        textLayer.alignmentMode = .left
        textLayer.truncationMode = .end
        container.addSublayer(textLayer)

        return container
    }
}

// MARK: - Highlight Item

struct HighlightItem {
    let frame: NSRect
    let fillColor: NSColor
    let borderColor: NSColor
    let color: OverlayColor
    let dashed: Bool
    let label: String?
    let id: String
    let animationType: AnimationType

    enum AnimationType {
        case fade
        case press
        case type
        case denied
    }

    init(
        frame: NSRect,
        color: OverlayColor,
        label: String? = nil,
        dashed: Bool = false,
        animationType: AnimationType = .fade,
        id: String = UUID().uuidString
    ) {
        self.frame = frame
        self.fillColor = color.fillColor
        self.borderColor = color.borderColor
        self.color = color
        self.dashed = dashed
        self.label = label
        self.id = id
        self.animationType = animationType
    }
}
