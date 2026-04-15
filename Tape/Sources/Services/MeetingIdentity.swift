import AppKit
import EventKit
import Foundation

/// Resolves meeting identity using a layered fallback chain:
/// 1. Calendar event currently in progress or starting within 5 min (EventKit)
/// 2. Window title of frontmost meeting app (Zoom, Teams, Meet, etc.)
/// 3. Frontmost app name
struct MeetingIdentity {
    let title: String
    let source: String

    /// Delegates to MicAllowlist so we maintain a single source of truth.
    private static var meetingApps: [String: String] { MicAllowlist.defaultAllowlist }

    /// Long-lived store — EventKit objects become invalid if the store is released.
    private static let store = EKEventStore()

    @MainActor
    static func resolve() async -> MeetingIdentity {
        // If Tape itself is frontmost (user opened the popover to hit Record),
        // look for a running meeting app instead of returning "tape".
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let effectiveApp: NSRunningApplication?
        if frontmostApp?.bundleIdentifier == "com.legare.tape" {
            effectiveApp = NSWorkspace.shared.runningApplications.first {
                meetingApps[$0.bundleIdentifier ?? ""] != nil
            }
        } else {
            effectiveApp = frontmostApp
        }

        let bundleID = effectiveApp?.bundleIdentifier ?? ""
        let appName = meetingApps[bundleID] ?? effectiveApp?.localizedName ?? "Unknown"

        // Layer 1: Calendar event currently in progress or starting within 5 min
        if let calendarTitle = await calendarMatch() {
            return MeetingIdentity(title: calendarTitle, source: appName)
        }

        // Layer 2: Try to read window title from the frontmost app
        if let windowTitle = getWindowTitle(for: effectiveApp), !windowTitle.isEmpty {
            let cleaned = cleanWindowTitle(windowTitle, appName: appName)
            if !cleaned.isEmpty {
                return MeetingIdentity(title: cleaned, source: appName)
            }
        }

        // Layer 3: Fallback to just the app name — date/time is already in the filename and frontmatter
        return MeetingIdentity(title: appName, source: appName)
    }

    // MARK: - Calendar matching

    /// Returns the title of the best-matching calendar event, or nil to fall through.
    /// Silently returns nil on permission denial, restricted access, or any error.
    private static func calendarMatch() async -> String? {
        // Check existing authorization before prompting
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess:
            break // already authorized — proceed to fetch
        case .notDetermined:
            // Request access — OS shows the permission dialog once
            guard (try? await store.requestFullAccessToEvents()) == true else { return nil }
        case .denied, .restricted, .writeOnly:
            return nil
        @unknown default:
            return nil
        }

        let now = Date()
        // Broad predicate window: covers long in-progress meetings (up to 4 hours) and upcoming ones (5 min)
        let windowStart = now.addingTimeInterval(-4 * 3600)
        let windowEnd = now.addingTimeInterval(5 * 60)

        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)

        // events(matching:) is synchronous — run off the main thread
        let events = await Task.detached(priority: .userInitiated) {
            store.events(matching: predicate)
        }.value

        let fiveMinutes: TimeInterval = 5 * 60
        let candidates = events.filter { event in
            guard !event.isAllDay else { return false }
            let inProgress = event.startDate <= now && event.endDate > now
            let startingSoon = event.startDate > now && event.startDate <= now.addingTimeInterval(fiveMinutes)
            return inProgress || startingSoon
        }

        // Most recently started event = the meeting the user just joined
        let best = candidates.sorted { $0.startDate > $1.startDate }.first
        let title = best?.title.trimmingCharacters(in: .whitespaces)
        return (title?.isEmpty == false) ? title : nil
    }

    // MARK: - Window title helpers

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
