import AppKit
import Foundation

/// Represents a single app in the mic detection allowlist UI.
struct AppEntry: Identifiable, Hashable {
    let bundleID: String
    let displayName: String
    var icon: NSImage?

    var id: String { bundleID }

    static func == (lhs: AppEntry, rhs: AppEntry) -> Bool { lhs.bundleID == rhs.bundleID }
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }

    /// Resolves display name and icon from the installed app bundle.
    /// Falls back to `fallbackName` or the bundle ID if the app isn't installed.
    static func resolve(bundleID: String, fallbackName: String? = nil) -> AppEntry {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name: String
        if let url {
            name = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
        } else {
            name = fallbackName ?? bundleID
        }
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        return AppEntry(bundleID: bundleID, displayName: name, icon: icon)
    }
}
