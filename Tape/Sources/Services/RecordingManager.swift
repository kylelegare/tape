import AppKit
import Foundation

/// Orchestrates the full recording lifecycle.
///
/// Manual flow: user taps Record → recording starts immediately.
///              user taps Stop  → audio captured → transcribed in background → .md saved.
@MainActor
final class RecordingManager: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var statusMessage: String?
    @Published var isTranscribing = false

    private var isFinalizing = false

    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    // MARK: - Static date formatters (DateFormatter is expensive to allocate)

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fileTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH-mm"
        return f
    }()

    // MARK: - Public entry points

    func beginRecording() {
        Task { await startRecording() }
    }

    func stopRecording() {
        Task { await finalizeRecording() }
    }

    // MARK: - Core Recording Logic

    private func startRecording() async {
        guard state == .idle else { return }
        state = .recording

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

        // Snapshot settings before cleanup so the transcription Task is fully independent
        var vocabulary: [String] = []
        if let json = UserDefaults.standard.string(forKey: "customVocabulary"),
           let data = json.data(using: .utf8),
           let words = try? JSONDecoder().decode([String].self, from: data) {
            vocabulary = words
        }
        let userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        let speakerName = userName.isEmpty ? "Speaker 1" : userName
        let whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "tiny"
        let title = Self.titleFormatter.string(from: capturedStartTime ?? Date())

        // Return to idle immediately — next recording can start while this transcribes
        isFinalizing = false
        cleanup()

        let service = transcriptionService
        Task {
            isTranscribing = true
            statusMessage = "transcribing…"

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

                writeMeetingFile(title: title, duration: duration, startTime: capturedStartTime, speakerName: speakerName, transcript: transcript)
                statusMessage = "saved — \(title)"
            } catch {
                writeMeetingFile(
                    title: title,
                    duration: duration,
                    startTime: capturedStartTime,
                    speakerName: speakerName,
                    transcript: "[transcription failed: \(error.localizedDescription)]",
                    partial: true
                )
                statusMessage = "transcription failed"
            }

            isTranscribing = false

            try? FileManager.default.removeItem(at: tracks.micURL)
            if let sysURL = tracks.systemURL { try? FileManager.default.removeItem(at: sysURL) }

            try? await Task.sleep(for: .seconds(3))
            if statusMessage?.starts(with: "saved") == true {
                statusMessage = nil
            }
        }
    }

    // MARK: - Markdown Output

    private func writeMeetingFile(title: String, duration: TimeInterval, startTime: Date?, speakerName: String, transcript: String, partial: Bool = false) {
        let outputDir = URL(fileURLWithPath: resolvedOutputFolder())
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let startDate = startTime ?? Date()
        let dateString = Self.dateFormatter.string(from: startDate)
        let timeString = Self.timeFormatter.string(from: startDate)
        let fileTimeString = Self.fileTimeFormatter.string(from: startDate)

        let slug = title
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
            .prefix(60)

        let filename = "\(dateString)-\(fileTimeString)-\(slug).md"
        let fileURL = outputDir.appendingPathComponent(filename)

        let durationMinutes = Int(duration / 60)
        let escapedTitle = title.contains(":") ? "\"\(title)\"" : title
        let content = """
        ---
        title: \(escapedTitle)
        date: \(dateString)
        time: \(timeString)
        duration: \(durationMinutes)min
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
    }
}
