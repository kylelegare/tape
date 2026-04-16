import Foundation

// MARK: - Output folder helpers

/// Returns the default tape output folder path (~/Documents/tape), creating it if needed.
func tapeOutputFolder() -> String {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let tapePath = documents.appendingPathComponent("tape")
    try? FileManager.default.createDirectory(at: tapePath, withIntermediateDirectories: true)
    return tapePath.path
}

/// Returns the user-configured output folder path, falling back to the default.
func resolvedOutputFolder() -> String {
    UserDefaults.standard.string(forKey: "outputFolderPath") ?? tapeOutputFolder()
}
