import AppKit
import Foundation

// MARK: - Design Tokens

/// Central place for all overlay design values.
/// Modeled after Apple's HIG: soft fills, vibrant borders, spring physics.
enum DesignTokens {
    // Corner radii (Apple standard: 10-12 for panels, 8 for cards, 6 for small elements)
    static let panelCornerRadius: CGFloat = 12
    static let highlightCornerRadius: CGFloat = 10
    static let labelCornerRadius: CGFloat = 8

    // Highlight geometry
    static let highlightInset: CGFloat = -3          // Outward padding around element
    static let highlightBorderWidth: CGFloat = 2.0
    static let highlightDashedWidth: CGFloat = 1.5
    static let dashPattern: [NSNumber] = [5, 3]

    // Label geometry
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let labelPadding: CGFloat = 7
    static let labelVerticalPadding: CGFloat = 4
    static let labelOffset: CGFloat = 6              // Gap between highlight and label
    static let labelBackgroundAlpha: CGFloat = 0.72

    // Status bar geometry
    static let statusBarWidth: CGFloat = 380
    static let statusBarHeight: CGFloat = 110
    static let statusBarTopInset: CGFloat = 48
    static let statusBarMaxEntries = 5

    // Spring animation (Apple-style bounce)
    static let springDamping: CGFloat = 0.72
    static let springInitialVelocity: CGFloat = 0.4
    static let springStiffness: CGFloat = 180
    static let springMass: CGFloat = 1.0

    // Press ripple
    static let pressScalePeak: CGFloat = 1.06

    // Type cursor blink
    static let cursorBlinkDuration: CFTimeInterval = 0.55
    static let cursorBlinkMinAlpha: CGFloat = 0.15

    // Auto-remove hold times (multipliers on animationSpeed.duration)
    static let observeHold: Double = 2.5
    static let pressHold: Double = 3.5
    static let typeHold: Double = 5.0
    static let selectHold: Double = 3.5
    static let keyHold: Double = 3.5
    static let deniedHold: Double = 5.0
    static let planHold: Double = 5.0
}

// MARK: - Action Colors

/// Action-specific colors. Uses system semantic colors so they adapt
/// to light/dark mode and accent color preferences.
public enum OverlayColor {
    case observe
    case press
    case type
    case select
    case key
    case navigate
    case scroll
    case denied
    case prompt

    public var fillColor: NSColor {
        switch self {
        case .observe:  return NSColor.systemGray.withAlphaComponent(0.12)
        case .press:    return NSColor.controlAccentColor.withAlphaComponent(0.18)
        case .type:     return NSColor.systemGreen.withAlphaComponent(0.15)
        case .select:   return NSColor.systemPurple.withAlphaComponent(0.15)
        case .key:      return NSColor.systemOrange.withAlphaComponent(0.15)
        case .navigate: return NSColor.labelColor.withAlphaComponent(0.08)
        case .scroll:   return NSColor.systemGray.withAlphaComponent(0.08)
        case .denied:   return NSColor.systemRed.withAlphaComponent(0.18)
        case .prompt:   return NSColor.systemYellow.withAlphaComponent(0.15)
        }
    }

    public var borderColor: NSColor {
        switch self {
        case .observe:  return NSColor.systemGray.withAlphaComponent(0.35)
        case .press:    return NSColor.controlAccentColor.withAlphaComponent(0.7)
        case .type:     return NSColor.systemGreen.withAlphaComponent(0.6)
        case .select:   return NSColor.systemPurple.withAlphaComponent(0.6)
        case .key:      return NSColor.systemOrange.withAlphaComponent(0.6)
        case .navigate: return NSColor.labelColor.withAlphaComponent(0.25)
        case .scroll:   return NSColor.systemGray.withAlphaComponent(0.2)
        case .denied:   return NSColor.systemRed.withAlphaComponent(0.7)
        case .prompt:   return NSColor.systemYellow.withAlphaComponent(0.6)
        }
    }

    /// The label pill background — slightly tinted with the action color.
    public var labelBackground: NSColor {
        switch self {
        case .denied:   return NSColor.systemRed.withAlphaComponent(0.85)
        case .prompt:   return NSColor.systemYellow.withAlphaComponent(0.85)
        default:        return NSColor.black.withAlphaComponent(DesignTokens.labelBackgroundAlpha)
        }
    }

    public static func forAction(_ action: String) -> OverlayColor {
        switch action.lowercased() {
        case "observe":  return .observe
        case "press":    return .press
        case "type":     return .type
        case "select":   return .select
        case "key":      return .key
        case "navigate": return .navigate
        case "scroll":   return .scroll
        default:         return .observe
        }
    }
}

// MARK: - Animation Speed

public enum AnimationSpeed: String {
    case fast   = "fast"
    case normal = "normal"
    case slow   = "slow"

    public var duration: TimeInterval {
        switch self {
        case .fast:   return 0.15
        case .normal: return 0.3
        case .slow:   return 0.6
        }
    }

    /// Fade-out is slightly longer than fade-in for a natural feel.
    public var fadeOutDuration: TimeInterval {
        duration * 1.8
    }

    /// Spring duration is longer to let the bounce settle.
    public var springDuration: TimeInterval {
        duration * 2.5
    }
}

// MARK: - Config

public struct OverlayConfig {
    public var enabled: Bool
    public var statusBar: Bool
    public var animationSpeed: AnimationSpeed

    public init(enabled: Bool = false, statusBar: Bool = true, animationSpeed: AnimationSpeed = .normal) {
        self.enabled = enabled
        self.statusBar = statusBar
        self.animationSpeed = animationSpeed
    }
}
