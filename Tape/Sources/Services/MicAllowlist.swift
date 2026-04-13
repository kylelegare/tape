import AppKit
import Foundation

/// Owns the mic-detection allowlist — which apps can trigger a recording prompt.
///
/// Storage is delta-only: only explicit user overrides are persisted so that
/// future default changes take effect automatically.
///   - `micAllowlistOverrides` — bundle IDs turned OFF from the defaults
///   - `micAllowlistAdditions` — bundle IDs turned ON by the user (non-defaults)
final class MicAllowlist: ObservableObject {

    // MARK: - Default allowlist

    static let defaultAllowlist: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "com.apple.FaceTime": "FaceTime",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "Brave Browser",
        "com.skype.skype": "Skype",
        "com.ringcentral.ringcentral": "RingCentral",
        "org.whispersystems.signal-desktop": "Signal",
        "net.whatsapp.WhatsApp": "WhatsApp",
    ]

    // MARK: - State

    /// Non-default apps that MicWatcher has seen using the mic.
    @Published var discoveredApps: [AppEntry] = []

    /// Called after every toggle so callers (e.g. MicWatcher) can re-evaluate state.
    var onToggle: (() -> Void)?

    // MARK: - Computed enabled set

    var enabledBundleIDs: Set<String> {
        let defaults = Set(Self.defaultAllowlist.keys)
        let overrides = storedArray(forKey: overridesKey)
        let additions = storedArray(forKey: additionsKey)
        return defaults.subtracting(overrides).union(additions)
    }

    func isEnabled(_ bundleID: String) -> Bool {
        enabledBundleIDs.contains(bundleID)
    }

    // MARK: - Toggle

    func toggle(_ bundleID: String) {
        if Self.defaultAllowlist[bundleID] != nil {
            var overrides = storedArray(forKey: overridesKey)
            if overrides.contains(bundleID) {
                overrides.removeAll { $0 == bundleID }
            } else {
                overrides.append(bundleID)
            }
            UserDefaults.standard.set(overrides, forKey: overridesKey)
        } else {
            var additions = storedArray(forKey: additionsKey)
            if additions.contains(bundleID) {
                additions.removeAll { $0 == bundleID }
            } else {
                additions.append(bundleID)
            }
            UserDefaults.standard.set(additions, forKey: additionsKey)
        }
        objectWillChange.send()
        onToggle?()
    }

    // MARK: - Discovery (called by MicWatcher on main thread)

    /// Records any non-default bundle IDs seen using the mic, for display in Settings.
    func updateDiscovered(_ bundleIDs: [String]) {
        let novel = bundleIDs.filter { Self.defaultAllowlist[$0] == nil && $0 != "com.legare.tape" }
        guard !novel.isEmpty else { return }

        var existing = discoveredApps
        for id in novel {
            let entry = AppEntry.resolve(bundleID: id)
            if !existing.contains(entry) {
                existing.append(entry)
            }
        }
        discoveredApps = existing.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Settings UI helpers

    /// Default apps that are actually installed, sorted by display name.
    /// Non-installed apps stay pre-allowed silently — they just don't clutter the UI.
    var defaultAppEntries: [AppEntry] {
        Self.defaultAllowlist
            .compactMap { bundleID, name -> AppEntry? in
                guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return nil }
                return AppEntry.resolve(bundleID: bundleID, fallbackName: name)
            }
            .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Private

    private let overridesKey = "micAllowlistOverrides"
    private let additionsKey = "micAllowlistAdditions"

    private func storedArray(forKey key: String) -> [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
}
