import AppKit
import Combine
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var calendarService: CalendarService!
    private var recordingManager: RecordingManager!
    private var meetingStore: MeetingStore!
    private var settingsWindow: NSWindow?
    private var stateCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        calendarService = CalendarService()
        recordingManager = RecordingManager(calendarService: calendarService)
        meetingStore = MeetingStore()

        setupMenuBar()
        setupNotifications()

        calendarService.startPeriodicSync()
        recordingManager.start()
        meetingStore.startWatching()

        stateCancellable = recordingManager.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            self?.updateStatusIcon(for: state)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncCalendarNow),
            name: .syncCalendar,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingManager.stop()
        calendarService.stopPeriodicSync()
        meetingStore.stopWatching()
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register "Record" / "Dismiss" actions for the mic-active prompt
        let recordAction = UNNotificationAction(
            identifier: "TAPE_RECORD",
            title: "Record",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: "TAPE_DISMISS",
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: "TAPE_MIC_ACTIVE",
            actions: [recordAction, dismissAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])

        // Request permission (alerts only — no sound, no badge)
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    // Show notification even when app is active (mic prompt should always be visible)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    // Handle "Record" action tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "TAPE_RECORD" {
            Task { @MainActor in
                self.recordingManager.startRecordingFromPrompt()
            }
        }
        completionHandler()
    }

    // MARK: - Menu Bar Icon

    private func cassetteIcon() -> NSImage? {
        guard let img = NSImage(named: "cassette") else {
            return NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "tape")
        }
        let copy = img.copy() as! NSImage
        copy.size = NSSize(width: 18, height: 18)
        copy.isTemplate = true
        return copy
    }

    private func updateStatusIcon(for state: RecordingState) {
        guard let button = statusItem?.button else { return }
        button.image = cassetteIcon()

        switch state {
        case .idle, .transcribing:
            // Plain cassette, no dot
            button.title = ""
            button.imagePosition = .imageOnly
        case .recording:
            // Red dot to the right of the cassette
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: 8, weight: .bold)
            ]
            button.attributedTitle = NSAttributedString(string: "●", attributes: attrs)
            button.imagePosition = .imageLeft
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = cassetteIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView(
                calendarService: calendarService,
                recordingManager: recordingManager,
                meetingStore: meetingStore
            )
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func syncCalendarNow() {
        Task { await calendarService.sync() }
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "tape"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
