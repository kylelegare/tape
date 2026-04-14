import Foundation
import WhisperKit

/// Transcribes audio files using WhisperKit (Core ML, Neural Engine).
/// Format conversion and VAD are handled internally by WhisperKit.
final class TranscriptionService {

    /// Cached WhisperKit instance. Loading a model is expensive — reuse it across
    /// both mic and system-audio transcription passes for the same recording.
    private var cache: (modelName: String, kit: WhisperKit)?

    struct TranscriptSegment {
        let text: String
        let startMs: Int
        let endMs: Int
        let speaker: String
    }

    /// Transcribe an audio file and return labeled segments.
    /// - Parameters:
    ///   - audioURL: Path to the audio file (CAF, m4a, or any AVFoundation-readable format)
    ///   - modelName: User-facing model name ("tiny", "base", "small", "medium", "large-v3")
    ///   - vocabulary: Custom vocabulary words — applied as post-processing corrections
    ///   - speakerName: Label applied to every segment returned (caller sets "Kyle" or "Others")
    func transcribe(
        audioURL: URL,
        modelName: String,
        vocabulary: [String],
        speakerName: String
    ) async throws -> [TranscriptSegment] {
        let whisperKitModelName = ModelManager.whisperKitID(for: modelName)
        let whisperKit: WhisperKit
        if let hit = cache, hit.modelName == whisperKitModelName {
            whisperKit = hit.kit
        } else {
            whisperKit = try await WhisperKit(model: whisperKitModelName, verbose: false, logLevel: .none)
            cache = (modelName: whisperKitModelName, kit: whisperKit)
        }

        let results: [TranscriptionResult] = try await whisperKit.transcribe(audioPath: audioURL.path)

        return results.flatMap { $0.segments }.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                text: text,
                startMs: Int(segment.start * 1000),
                endMs: Int(segment.end * 1000),
                speaker: speakerName
            )
        }
    }

    /// Format labeled segments into markdown with timestamps and speaker prefixes.
    func formatTranscript(segments: [TranscriptSegment]) -> String {
        segments.map { segment in
            let minutes = segment.startMs / 60_000
            let seconds = (segment.startMs % 60_000) / 1000
            let timestamp = String(format: "%d:%02d", minutes, seconds)
            return "**[\(timestamp)] \(segment.speaker):** \(segment.text)"
        }.joined(separator: "\n\n")
    }

    /// Apply custom vocabulary find/replace to clean up transcription output.
    func applyVocabularyCorrections(_ text: String, vocabulary: [String]) -> String {
        var result = text
        for word in vocabulary {
            let pattern = NSRegularExpression.escapedPattern(for: word)
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: word
                )
            }
        }
        return result
    }
}
