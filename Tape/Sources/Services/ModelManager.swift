import Foundation

/// Manages whisper model downloads and storage.
/// Models are stored in ~/Library/Application Support/Tape/models/
final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false

    static let shared = ModelManager()

    private let modelsDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Tape/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// HuggingFace base URL for whisper.cpp models
    private static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"

    /// Model filenames — using quantized variants for smaller size
    static let modelFiles: [String: String] = [
        "tiny": "ggml-tiny.bin",
        "base": "ggml-base.bin",
        "small": "ggml-small.bin",
        "medium": "ggml-medium.bin",
        "large-v3": "ggml-large-v3.bin",
    ]

    /// Check if a model is already downloaded
    func modelPath(for model: String) -> URL? {
        guard let filename = Self.modelFiles[model] else { return nil }
        let path = modelsDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Download a model if not present. Returns the local file path.
    func ensureModel(_ model: String) async throws -> URL {
        if let existing = modelPath(for: model) {
            return existing
        }

        guard let filename = Self.modelFiles[model] else {
            throw ModelError.unknownModel(model)
        }

        let remoteURL = URL(string: Self.baseURL + filename)!
        let localURL = modelsDir.appendingPathComponent(filename)

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloading = false
            }
        }

        let (tempURL, _) = try await URLSession.shared.download(from: remoteURL, delegate: DownloadDelegate { progress in
            Task { @MainActor in
                self.downloadProgress = progress
            }
        })

        try FileManager.default.moveItem(at: tempURL, to: localURL)
        return localURL
    }
}

enum ModelError: Error, LocalizedError {
    case unknownModel(String)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let name): return "Unknown whisper model: \(name)"
        }
    }
}

/// URLSession download delegate that reports progress
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by the async download call
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
