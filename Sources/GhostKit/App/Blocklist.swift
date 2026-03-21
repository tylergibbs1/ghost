import Foundation

/// Hard-coded blocklist of CLI applications that should not be accessed via Ghost.
/// Ghost is for GUI-only apps. CLI apps should use bash.
public struct Blocklist {
    public init() {}

    private static let blockedApps: Set<String> = [
        "terminal",
        "iterm2",
        "iterm",
        "warp",
        "alacritty",
        "kitty",
        "hyper",
        "rio",
        "wezterm",
        "tabby",
        "ghostty",
    ]

    /// Check if an app name is blocklisted. Throws GhostError.blockedApp if so.
    public func check(appName: String) throws {
        let normalized = appName.lowercased()
        if Self.blockedApps.contains(normalized) {
            throw GhostError.blockedApp(name: appName)
        }
    }
}
