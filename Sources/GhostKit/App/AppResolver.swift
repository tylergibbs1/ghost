import AppKit
import Foundation

/// Finds running macOS applications by name.
public struct AppResolver {
    public init() {}

    /// Find a running application by name (case-insensitive partial match).
    /// Returns the best match or throws if not found.
    public func resolve(name: String) throws -> NSRunningApplication {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        // Exact match first (case-insensitive)
        if let exact = apps.first(where: {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return exact
        }

        // Prefix match
        if let prefix = apps.first(where: {
            $0.localizedName?.lowercased().hasPrefix(name.lowercased()) == true
        }) {
            return prefix
        }

        // Contains match
        if let contains = apps.first(where: {
            $0.localizedName?.lowercased().contains(name.lowercased()) == true
        }) {
            return contains
        }

        // Bundle ID match as fallback
        if let bundle = apps.first(where: {
            $0.bundleIdentifier?.lowercased().contains(name.lowercased()) == true
        }) {
            return bundle
        }

        throw GhostError.appNotFound(name: name)
    }

    /// List all running GUI applications.
    public func listRunning() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
