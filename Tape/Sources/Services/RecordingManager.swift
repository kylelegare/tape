import AppKit
import Foundation

/// Orchestrates the full recording lifecycle.
///
/// Flow: user taps Record → recording starts → user taps Stop → transcribe → .md saved.
@MainActor
final class RecordingManager: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var currentMeetingTitle: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var statusMessage: String?

    private var isFinalizing = false

    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private var recordingStartTime: Date?
    private var audioFileURL: URL?
    private var durationTimer: Timer?
    private var meetingIdentity: MeetingIdentity?

    // MARK: - Public recording entry points

    /// Called by the manual Record button in the popover.
    func startOneOffRecording() {
        let identity = MeetingIdentity.resolve()
        Task { await startRecording(identity: identity) }
    }

    /// Stop whatever is currently recording.
    func stopRecording() {
        Task { await finalizeRecording() }
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
        } catch {
            statusMessage = "recording failed: \(error.localizedDescription)"
        }
    }

    private func finalizeRecording() async {
        guard !isFinalizing else { return }
        isFinalizing = true
        defer { isFinalizing = false }

        stopDurationTimer()

        let duration = recordingDuration
        let minimumDuration = TimeInterval(UserDefaults.standard.integer(forKey: "minimumDuration"))
        // Default minimum: 5 seconds — just enough to discard accidental taps
        let minSeconds = minimumDuration > 0 ? minimumDuration : 5

        await audioRecorder.stopRecording()

        if duration < minSeconds {
            if let audioURL = audioFileURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
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
        let whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "tiny"

        do {
            if ModelManager.shared.modelPath(for: whisperModel) == nil {
                statusMessage = "downloading \(whisperModel) model…"
            } else {
                statusMessage = "transcribing — \(identity.title)"
            }
            let modelPath = try await ModelManager.shared.ensureModel(whisperModel)
            statusMessage = "transcribing — \(identity.title)"

            var result = try await transcriptionService.transcribe(
                audioURL: audioURL,
                modelPath: modelPath,
                vocabulary: vocabulary,
                speakerName: userName
            )

            // Filter out hallucinated segments that fall in non-speech regions
            let filtered = try await transcriptionService.filterHallucinations(
                segments: result.segments, audioURL: audioURL
            )
            result = TranscriptionService.TranscriptResult(
                segments: filtered, speakerName: result.speakerName
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
    }
}
