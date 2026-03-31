import AppKit
import Combine
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var popoverWindow: NSWindow?
    private var eventMonitor: Any?
    private var recordingManager: RecordingManager!
    private var meetingStore: MeetingStore!
    private var settingsWindow: NSWindow?
    private var stateCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register factory defaults so UserDefaults.integer(forKey:) returns sensible values
        // even before the user opens Settings. graceWindowDuration 0 means "off" (immediate stop).
        UserDefaults.standard.register(defaults: [
            "graceWindowDuration": 30,
            "minimumDuration": 5
        ])

        recordingManager = RecordingManager()
        meetingStore = MeetingStore()

        setupMenuBar()
        setupNotifications()

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

    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingManager.stop()
        meetingStore.stopWatching()
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register "Record" / "Dismiss" actions for the mic-active prompt
        let recordAction = UNNotificationAction(
            identifier: TapeNotificationID.actionRecord,
            title: "Record",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: TapeNotificationID.actionDismiss,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: TapeNotificationID.categoryMicActive,
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
        if response.actionIdentifier == TapeNotificationID.actionRecord {
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
    }

    @objc private func togglePopover() {
        if popoverWindow != nil {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let hosting = NSHostingController(
            rootView: MainPopoverView(
                recordingManager: recordingManager,
                meetingStore: meetingStore
            )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false

        // Position flush below the status bar button
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)

        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 420
        var x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.minY - windowHeight

        // Keep within screen bounds
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(screenFrame.origin) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = max(visible.minX + 4, min(x, visible.maxX - windowWidth - 4))
        }

        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        popoverWindow = window

        // Dismiss on click outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popoverWindow?.orderOut(nil)
        popoverWindow = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        NSApp.activate()
        settingsWindow = window
    }
}
