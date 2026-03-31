import AVFoundation
import Foundation
import SwiftWhisper

/// Transcribes audio files using whisper.cpp via SwiftWhisper.
/// Handles audio format conversion (48kHz → 16kHz mono float) and vocabulary injection.
final class TranscriptionService {

    struct TranscriptResult {
        let segments: [TranscriptSegment]
        let speakerName: String
    }

    struct TranscriptSegment {
        let text: String
        let startMs: Int
        let endMs: Int
    }

    /// Transcribe an audio file and return segments.
    /// - Parameters:
    ///   - audioURL: Path to the .m4a recording
    ///   - modelPath: Path to the whisper .bin model file
    ///   - vocabulary: Custom vocabulary words for initial prompt biasing
    ///   - speakerName: User's configured name (for speaker labeling)
    func transcribe(
        audioURL: URL,
        modelPath: URL,
        vocabulary: [String],
        speakerName: String
    ) async throws -> TranscriptResult {
        // Convert audio to 16kHz mono float samples (whisper requirement)
        let samples = try await loadAudioSamples(from: audioURL)

        // Set up whisper
        let whisper = Whisper(fromFileURL: modelPath)

        // Configure params with vocabulary as initial prompt
        if !vocabulary.isEmpty {
            let prompt = vocabulary.joined(separator: ", ")
            whisper.params.initial_prompt = UnsafePointer(strdup(prompt))
        }

        // Run transcription
        let segments = try await whisper.transcribe(audioFrames: samples)

        let result = segments.map { segment in
            TranscriptSegment(
                text: segment.text.trimmingCharacters(in: .whitespaces),
                startMs: segment.startTime,
                endMs: segment.endTime
            )
        }

        return TranscriptResult(segments: result, speakerName: speakerName)
    }

    /// Format transcript segments into markdown with speaker labels.
    /// mic audio = user's name, system audio = "Speaker 2"
    func formatTranscript(result: TranscriptResult) -> String {
        let name = result.speakerName.isEmpty ? "Speaker 1" : result.speakerName

        // For V1, all transcript text is attributed to the combined stream.
        // Speaker separation: mic = user, system = others.
        // Since both tracks are in the same file, we label the whole transcript.
        // True diarization would require analyzing which track each segment came from.
        return result.segments.map { segment in
            "**\(name):** \(segment.text)"
        }.joined(separator: "\n\n")
    }

    /// Apply custom vocabulary find/replace to clean up transcription output
    func applyVocabularyCorrections(_ text: String, vocabulary: [String]) -> String {
        var result = text
        for word in vocabulary {
            // Case-insensitive replacement with correct form
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

    // MARK: - Audio Loading

    /// Load audio file and convert to 16kHz mono Float32 samples
    private func loadAudioSamples(from url: URL) async throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let sourceFormat = audioFile.processingFormat

        // Target format: 16kHz, mono, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.invalidFormat
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw TranscriptionError.converterFailed
        }

        // Calculate output frame count
        let ratio = 16000.0 / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(audioFile.length) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            throw TranscriptionError.bufferFailed
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            let frameCount: AVAudioFrameCount = 4096
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
                outStatus.pointee = .noDataNow
                return nil
            }

            do {
                try audioFile.read(into: buffer)
                outStatus.pointee = buffer.frameLength > 0 ? .haveData : .endOfStream
                return buffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            throw error
        }

        guard let floatData = outputBuffer.floatChannelData else {
            throw TranscriptionError.noData
        }

        return Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))
    }
}

enum TranscriptionError: Error, LocalizedError {
    case invalidFormat
    case converterFailed
    case bufferFailed
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Could not create target audio format"
        case .converterFailed: return "Could not create audio converter"
        case .bufferFailed: return "Could not create audio buffer"
        case .noData: return "No audio data after conversion"
        }
    }
}
