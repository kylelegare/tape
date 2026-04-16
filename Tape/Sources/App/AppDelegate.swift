import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var popoverWindow: NSWindow?
    private var eventMonitor: Any?
    private var recordingManager: RecordingManager!
    private var meetingStore: MeetingStore!
    private var settingsWindow: NSWindow?
    private var stateCancellable: AnyCancellable?
    private var transientStatusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }

        UserDefaults.standard.register(defaults: [
            "minimumDuration": 5,
            "whisperModel": "tiny"
        ])

        recordingManager = RecordingManager()
        meetingStore = MeetingStore()

        setupMenuBar()
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
        guard !isRunningTests else { return }
        meetingStore.stopWatching()
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
        case .idle:
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
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        let isSecondaryClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))

        if isSecondaryClick {
            showStatusMenu()
        } else {
            togglePopover()
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

    private func showStatusMenu() {
        closePopover()

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Tape", action: #selector(showTapeFromMenu), keyEquivalent: ""))

        let recordingItemTitle: String
        let recordingItemEnabled: Bool

        switch recordingManager.state {
        case .idle:
            recordingItemTitle = "Start Recording"
            recordingItemEnabled = true
        case .recording:
            recordingItemTitle = "Stop Recording"
            recordingItemEnabled = true
        }

        let recordingItem = NSMenuItem(title: recordingItemTitle, action: #selector(toggleRecordingFromMenu), keyEquivalent: "")
        recordingItem.isEnabled = recordingItemEnabled
        menu.addItem(recordingItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tape", action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        menu.delegate = self
        transientStatusMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    @objc private func showTapeFromMenu() {
        if popoverWindow == nil {
            showPopover()
        }
    }

    @objc private func toggleRecordingFromMenu() {
        switch recordingManager.state {
        case .idle:
            recordingManager.beginRecording()
        case .recording:
            recordingManager.stopRecording()
        }
    }

    @objc private func openRecordingsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: resolvedOutputFolder()))
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        if transientStatusMenu === menu {
            statusItem.menu = nil
            transientStatusMenu = nil
        }
    }

    @objc func openSettings() {
        closePopover()

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 420),
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
