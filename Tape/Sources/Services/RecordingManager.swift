import AppKit
import Foundation
import UserNotifications

/// Orchestrates the full recording lifecycle.
///
/// Auto-detection flow (signed build):
///   mic grabbed → notification prompt → user taps "Record" → recording starts
///   mic released → grace window → finalize → transcribe → .md saved
///
/// Manual flow: user taps Record button in the popover.
@MainActor
final class RecordingManager: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var currentMeetingTitle: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var statusMessage: String?

    private var isFinalizing = false

    let allowlist = MicAllowlist()

    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private let micWatcher = MicWatcher()
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var meetingIdentity: MeetingIdentity?
    private var graceWindowTask: Task<Void, Never>?
    /// The most recently active allowlist app (excluding Tape itself).
    /// Used so MeetingIdentity can pick the right app when Tape is frontmost.
    private(set) var lastActiveMeetingApp: NSRunningApplication?
    private var appActivationObserver: Any?

    // MARK: - Lifecycle

    func start() {
        micWatcher.allowlist = allowlist
        micWatcher.onMicGrabbed = { [weak self] in
            Task { @MainActor in self?.handleMicGrabbed() }
        }
        micWatcher.onMicReleased = { [weak self] in
            Task { @MainActor in self?.handleMicReleased() }
        }
        allowlist.onToggle = { [weak self] in
            self?.micWatcher.reevaluate()
        }
        micWatcher.start()

        // Track which meeting app the user was in before opening the popover
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != "com.legare.tape",
                  MicAllowlist.defaultAllowlist[app.bundleIdentifier ?? ""] != nil
            else { return }
            Task { @MainActor in self.lastActiveMeetingApp = app }
        }
    }

    func stop() {
        micWatcher.stop()
        graceWindowTask?.cancel()
        graceWindowTask = nil
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
    }

    // MARK: - Mic detection handlers

    private func handleMicGrabbed() {
        graceWindowTask?.cancel()
        graceWindowTask = nil
        guard state == .idle else { return }
        sendRecordPrompt()
    }

    private func handleMicReleased() {
        guard state == .recording else { return }
        let grace = UserDefaults.standard.integer(forKey: "graceWindowDuration")
        let graceDuration = grace > 0 ? TimeInterval(grace) : 30
        graceWindowTask = Task {
            try? await Task.sleep(for: .seconds(graceDuration))
            guard !Task.isCancelled else { return }
            await self.finalizeRecording()
        }
    }

    private func sendRecordPrompt() {
        let content = UNMutableNotificationContent()
        content.title = "Meeting started"
        content.body = "Tap Record to capture this meeting"
        content.categoryIdentifier = TapeNotificationID.categoryMicActive
        let request = UNNotificationRequest(
            identifier: TapeNotificationID.categoryMicActive,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Public recording entry points

    /// Start a recording. Called from the popover button or mic-active notification.
    func beginRecording() {
        let hint = lastActiveMeetingApp
        Task {
            let identity = await MeetingIdentity.resolve(hint: hint)
            await startRecording(identity: identity)
        }
    }

    /// Stop whatever is currently recording.
    func stopRecording() {
        graceWindowTask?.cancel()
        graceWindowTask = nil
        Task { await finalizeRecording() }
    }

    // MARK: - Core Recording Logic

    private func startRecording(identity: MeetingIdentity) async {
        guard state == .idle else { return }
        // Set state before the first await so any concurrent Task racing through
        // this guard sees a non-idle state and exits cleanly.
        state = .recording
        meetingIdentity = identity
        currentMeetingTitle = identity.title

        do {
            try await audioRecorder.startRecording()
            recordingStartTime = Date()
            startDurationTimer()
        } catch {
            state = .idle
            statusMessage = "recording failed: \(error.localizedDescription)"
        }
    }

    private func finalizeRecording() async {
        guard state == .recording else { return }
        guard !isFinalizing else { return }
        isFinalizing = true

        stopDurationTimer()

        let duration = recordingDuration
        let capturedStartTime = recordingStartTime
        let minimumDuration = TimeInterval(UserDefaults.standard.integer(forKey: "minimumDuration"))
        let minSeconds = minimumDuration > 0 ? minimumDuration : 5

        guard let tracks = await audioRecorder.stopRecording() else {
            statusMessage = "recording failed"
            isFinalizing = false
            cleanup()
            return
        }

        if duration < minSeconds {
            try? FileManager.default.removeItem(at: tracks.mixedURL)
            try? FileManager.default.removeItem(at: tracks.micURL)
            if let sysURL = tracks.systemURL { try? FileManager.default.removeItem(at: sysURL) }
            statusMessage = "recording discarded (< \(Int(minSeconds))s)"
            isFinalizing = false
            cleanup()
            return
        }

        guard let identity = meetingIdentity else {
            isFinalizing = false
            cleanup()
            return
        }

        // Snapshot everything needed before cleanup so the transcription Task
        // is fully independent — a new recording can start immediately.
        var vocabulary: [String] = []
        if let json = UserDefaults.standard.string(forKey: "customVocabulary"),
           let data = json.data(using: .utf8),
           let words = try? JSONDecoder().decode([String].self, from: data) {
            vocabulary = words
        }
        let userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        let speakerName = userName.isEmpty ? "Speaker 1" : userName
        let whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "tiny"

        // Return to idle immediately — next recording can start while this transcribes
        isFinalizing = false
        cleanup()

        // Transcribe in background; statusMessage updates are visible in the menu bar
        // even while a new recording is in progress.
        let service = TranscriptionService()
        Task {
            statusMessage = "transcribing — \(identity.title)"

            do {
                let micSegments = try await service.transcribe(
                    audioURL: tracks.micURL,
                    modelName: whisperModel,
                    vocabulary: vocabulary,
                    speakerName: speakerName
                )

                var allSegments = micSegments
                if let sysURL = tracks.systemURL {
                    let sysSegments = try await service.transcribe(
                        audioURL: sysURL,
                        modelName: whisperModel,
                        vocabulary: vocabulary,
                        speakerName: "Others"
                    )
                    allSegments = (micSegments + sysSegments).sorted { $0.startMs < $1.startMs }
                }

                var transcript = service.formatTranscript(segments: allSegments)
                if !vocabulary.isEmpty {
                    transcript = service.applyVocabularyCorrections(transcript, vocabulary: vocabulary)
                }

                writeMeetingFile(identity: identity, duration: duration, startTime: capturedStartTime, transcript: transcript)
                statusMessage = "saved — \(identity.title)"
            } catch {
                writeMeetingFile(
                    identity: identity,
                    duration: duration,
                    startTime: capturedStartTime,
                    transcript: "[transcription failed: \(error.localizedDescription)]",
                    partial: true
                )
                statusMessage = "transcription failed — \(identity.title)"
            }

            try? FileManager.default.removeItem(at: tracks.micURL)
            if let sysURL = tracks.systemURL { try? FileManager.default.removeItem(at: sysURL) }

            try? await Task.sleep(for: .seconds(3))
            if statusMessage?.starts(with: "saved") == true {
                statusMessage = nil
            }
        }
    }

    // MARK: - Markdown Output

    private func writeMeetingFile(identity: MeetingIdentity, duration: TimeInterval, startTime: Date?, transcript: String, partial: Bool = false) {
        let outputDir = URL(fileURLWithPath: resolvedOutputFolder())

        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let startDate = startTime ?? date

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: startDate)

        let fileTimeFormatter = DateFormatter()
        fileTimeFormatter.dateFormat = "HH-mm"
        let fileTimeString = fileTimeFormatter.string(from: startDate)

        let slug = identity.title
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .prefix(60)

        let filename = "\(dateString)-\(fileTimeString)-\(slug).md"
        let fileURL = outputDir.appendingPathComponent(filename)

        let durationMinutes = Int(duration / 60)
        let userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        let speakerName = userName.isEmpty ? "Speaker 1" : userName

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
        meetingIdentity = nil
        currentMeetingTitle = nil
    }
}
