import Foundation

/// Maps user-facing Whisper model names to WhisperKit identifiers.
/// Download, caching, and Core ML compilation are handled by WhisperKit internally.
enum ModelManager {

    /// User-facing model names shown in Settings.
    static let availableModels = ["tiny", "base", "small", "medium", "large-v3"]

    /// Translate a user-facing model name to the WhisperKit model identifier.
    static func whisperKitID(for modelName: String) -> String {
        switch modelName {
        case "tiny":    return "openai_whisper-tiny"
        case "base":    return "openai_whisper-base"
        case "small":   return "openai_whisper-small"
        case "medium":  return "openai_whisper-medium"
        case "large-v3": return "openai_whisper-large-v3"
        default:        return "openai_whisper-tiny"
        }
    }
}
