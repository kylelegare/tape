import AppKit
import Foundation
import UserNotifications

/// Orchestrates the full recording lifecycle.
///
/// Auto-detection flow (requires signed build):
///   mic active → notification prompt → user taps "Record" → recording starts
///   mic released OR meeting app closes → grace window → finalize → transcribe → .md
///
/// Manual flow: user taps Record button in the popover.
@MainActor
final class RecordingManager: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var currentMeetingTitle: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var statusMessage: String?

    private var isFinalizing = false

    private let audioRecorder = AudioRecorder()
    private let micWatcher = MicWatcher()
    private let transcriptionService = TranscriptionService()
    private var recordingStartTime: Date?
    private var audioFileURL: URL?
    private var durationTimer: Timer?
    private var graceTimer: Timer?
    private var meetingPollTimer: Timer?
    private var meetingIdentity: MeetingIdentity?

    /// Meeting apps that were running when recording started — used to detect end-of-meeting.
    private var trackedMeetingApps: Set<String> = []

    /// ID of the in-flight mic-active notification, so we can dismiss it on response or mic release.
    private var pendingNotificationID: String?

    /// Known meeting apps to watch for auto-stop. Excludes browsers (always running).
    private static let meetingAppBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.apple.FaceTime",
        "com.tinyspeck.slackmacgap",
    ]

    init() {
        setupMicWatcher()
    }

    func start() {
        // Mic detection (auto-prompt on mic grab) requires a signed/notarized build —
        // macOS Sequoia privacy APIs return incorrect state for unsigned debug builds.
        // Re-enable micWatcher.start() once distributed via Developer ID or App Store.
        // micWatcher.start()
    }

    func stop() {
        micWatcher.stop()
    }

    // MARK: - Public recording entry points

    /// Called by AppDelegate when the user taps "Record" in the mic-active notification.
    func startRecordingFromPrompt() {
        pendingNotificationID = nil
        let identity = MeetingIdentity.resolve()
        Task { await startRecording(identity: identity) }
    }

    /// Called by the manual Record button in the popover — one-off note.
    func startOneOffRecording() {
        let identity = MeetingIdentity(title: "note", source: "Manual")
        Task { await startRecording(identity: identity) }
    }

    /// Stop whatever is currently recording.
    func stopRecording() {
        Task { await finalizeRecording() }
    }

    // MARK: - Mic Watcher

    private func setupMicWatcher() {
        micWatcher.onMicGrabbed = { [weak self] in
            Task { @MainActor in
                await self?.handleMicGrabbed()
            }
        }
        micWatcher.onMicReleased = { [weak self] in
            Task { @MainActor in
                self?.handleMicReleased()
            }
        }
    }

    /// Mic became active — prompt the user rather than auto-recording.
    private func handleMicGrabbed() async {
        guard state == .idle else { return }
        graceTimer?.invalidate()
        graceTimer = nil
        sendRecordingPrompt()
    }

    /// Mic released — dismiss any pending prompt; start grace window if we're recording.
    /// Note: this won't fire during an active recording because our own AVAudioEngine
    /// holds the mic. Meeting-end detection is handled by meetingPollTimer instead.
    private func handleMicReleased() {
        if let id = pendingNotificationID {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            pendingNotificationID = nil
        }
        guard state == .recording else { return }
        startGracePeriod()
    }

    // MARK: - Notification Prompt

    private func sendRecordingPrompt() {
        let content = UNMutableNotificationContent()
        content.title = "tape"

        content.body = "mic is active — record?"
        content.categoryIdentifier = TapeNotificationID.categoryMicActive
        content.sound = nil

        let notifID = "tape-mic-\(Int(Date().timeIntervalSince1970))"
        pendingNotificationID = notifID

        let request = UNNotificationRequest(identifier: notifID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        // Auto-dismiss after 8 seconds if not acted on
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard self?.pendingNotificationID == notifID else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notifID])
            self?.pendingNotificationID = nil
        }
    }

    // MARK: - Core Recording Logic

    private func startRecording(identity: MeetingIdentity) async {
        guard state == .idle else { return }
        meetingIdentity = identity
        currentMeetingTitle = identity.title

        do {
            let url = try await audioRecorder.startRecording()
            audioFileURL = url
            recordingStartTime = Date()
            state = .recording
            startDurationTimer()
            startMeetingPollIfNeeded()
        } catch {
            statusMessage = "recording failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Meeting End Detection

    /// Snapshot which known meeting apps are running at recording start.
    /// Polls every 10s to detect when they all close → triggers grace period.
    /// If no meeting apps were running (pure manual note), this is a no-op.
    private func startMeetingPollIfNeeded() {
        let running = NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleIdentifier }
            .filter { Self.meetingAppBundleIDs.contains($0) }

        trackedMeetingApps = Set(running)
        guard !trackedMeetingApps.isEmpty else { return } // manual note — no poll needed

        meetingPollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .recording else {
                    self?.meetingPollTimer?.invalidate()
                    return
                }
                let stillRunning = NSWorkspace.shared.runningApplications
                    .compactMap { $0.bundleIdentifier }
                    .filter { self.trackedMeetingApps.contains($0) }

                if stillRunning.isEmpty {
                    self.meetingPollTimer?.invalidate()
                    self.meetingPollTimer = nil
                    self.startGracePeriod()
                }
            }
        }
    }

    private func startGracePeriod() {
        guard graceTimer == nil else { return } // already counting down
        let graceSeconds = UserDefaults.standard.integer(forKey: "graceWindowDuration")
        // 0 = "off" in Settings → stop immediately; default registered at launch is 30

        if graceSeconds == 0 {
            Task { await finalizeRecording() }
            return
        }

        statusMessage = "finishing in \(graceSeconds)s…"
        graceTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(graceSeconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.finalizeRecording()
            }
        }
    }

    private func finalizeRecording() async {
        guard !isFinalizing else { return }
        isFinalizing = true
        defer { isFinalizing = false }

        graceTimer?.invalidate()
        graceTimer = nil
        meetingPollTimer?.invalidate()
        meetingPollTimer = nil
        stopDurationTimer()

        let duration = recordingDuration
        let minimumDuration = TimeInterval(UserDefaults.standard.integer(forKey: "minimumDuration"))
        // Default minimum: 5 seconds — just enough to discard accidental taps
        let minSeconds = minimumDuration > 0 ? minimumDuration : 5

        await audioRecorder.stopRecording()

        if duration < minSeconds {
            statusMessage = "recording discarded (< \(Int(minSeconds))s)"
            cleanup()
            return
        }

        guard let audioURL = audioFileURL, let identity = meetingIdentity else {
            cleanup()
            return
        }

        state = .transcribing

        var vocabulary: [String] = []
        if let json = UserDefaults.standard.string(forKey: "customVocabulary"),
           let data = json.data(using: .utf8),
           let words = try? JSONDecoder().decode([String].self, from: data) {
            vocabulary = words
        }

        let userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        let whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "base"

        do {
            if ModelManager.shared.modelPath(for: whisperModel) == nil {
                statusMessage = "downloading \(whisperModel) model…"
            } else {
                statusMessage = "transcribing — \(identity.title)"
            }
            let modelPath = try await ModelManager.shared.ensureModel(whisperModel)
            statusMessage = "transcribing — \(identity.title)"

            let result = try await transcriptionService.transcribe(
                audioURL: audioURL,
                modelPath: modelPath,
                vocabulary: vocabulary,
                speakerName: userName
            )

            var transcript = transcriptionService.formatTranscript(result: result)
            if !vocabulary.isEmpty {
                transcript = transcriptionService.applyVocabularyCorrections(transcript, vocabulary: vocabulary)
            }

            writeMeetingFile(identity: identity, duration: duration, transcript: transcript)
            statusMessage = "saved — \(identity.title)"
        } catch {
            writeMeetingFile(
                identity: identity,
                duration: duration,
                transcript: "[transcription failed: \(error.localizedDescription)]",
                partial: true
            )
            statusMessage = "transcription failed — \(identity.title)"
        }

        cleanup()

        try? await Task.sleep(for: .seconds(3))
        if statusMessage?.starts(with: "saved") == true {
            statusMessage = nil
        }
    }

    // MARK: - Markdown Output

    private func writeMeetingFile(identity: MeetingIdentity, duration: TimeInterval, transcript: String, partial: Bool = false) {
        let outputDir = URL(fileURLWithPath: resolvedOutputFolder())

        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let startDate = recordingStartTime ?? date

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: startDate)

        // HH-mm in filename prevents silent overwrite when two recordings share the same title on the same day
        let fileTimeFormatter = DateFormatter()
        fileTimeFormatter.dateFormat = "HH-mm"
        let fileTimeString = fileTimeFormatter.string(from: startDate)

        let slug = identity.title
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")   // prevent path traversal
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .prefix(60)

        let filename = "\(dateString)-\(fileTimeString)-\(slug).md"
        let fileURL = outputDir.appendingPathComponent(filename)

        let durationMinutes = Int(duration / 60)
        let userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        let speakerName = userName.isEmpty ? "Speaker 1" : userName

        // Quote title in YAML to prevent frontmatter corruption if it contains a colon
        let escapedTitle = identity.title.contains(":") ? "\"\(identity.title)\"" : identity.title
        let content = """
        ---
        title: \(escapedTitle)
        date: \(dateString)
        time: \(timeString)
        duration: \(durationMinutes)min
        source: \(identity.source)
        speakers:
          - \(speakerName)
          - Speaker 2
        partial: \(partial)
        ---

        ## Context



        ## Transcript

        \(transcript)
        """

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            statusMessage = "failed to write transcript: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func startDurationTimer() {
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func cleanup() {
        state = .idle
        recordingDuration = 0
        recordingStartTime = nil
        audioFileURL = nil
        meetingIdentity = nil
        currentMeetingTitle = nil
        trackedMeetingApps = []
    }
}
