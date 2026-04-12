import AppKit
import Foundation

/// Resolves meeting identity using a layered fallback chain:
/// 1. Window title of frontmost meeting app (Zoom, Teams, Meet, etc.)
/// 2. ICS calendar event match (±15 min window)
/// 3. Frontmost app name + timestamp
struct MeetingIdentity {
    let title: String
    let source: String

    /// Delegates to MicAllowlist so we maintain a single source of truth.
    private static var meetingApps: [String: String] { MicAllowlist.defaultAllowlist }

    @MainActor
    static func resolve() -> MeetingIdentity {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApp?.bundleIdentifier ?? ""
        let appName = meetingApps[bundleID] ?? frontmostApp?.localizedName ?? "Unknown"

        // Layer 1: Try to read window title from the frontmost app
        if let windowTitle = getWindowTitle(for: frontmostApp), !windowTitle.isEmpty {
            let cleaned = cleanWindowTitle(windowTitle, appName: appName)
            if !cleaned.isEmpty {
                return MeetingIdentity(title: cleaned, source: appName)
            }
        }

        // Layer 2: Fallback to app name + timestamp
        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
        return MeetingIdentity(title: "\(appName) — \(timestamp)", source: appName)
    }

    /// Read the window title of an app via Accessibility API
    private static func getWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let app, let pid = Optional(app.processIdentifier) else { return nil }

        let appRef = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue) == .success
        else { return nil }

        let window = windowValue as! AXUIElement
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success
        else { return nil }

        return titleValue as? String
    }

    private static func cleanWindowTitle(_ title: String, appName: String) -> String {
        var cleaned = title
        // Remove common suffixes
        let suffixes = [
            " - Zoom Meeting", " - Zoom", " | Microsoft Teams",
            " - Teams", " - Google Meet", " - Webex",
            " - FaceTime", " - Slack",
        ]
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
