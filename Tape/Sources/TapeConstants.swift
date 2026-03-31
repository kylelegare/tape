import Foundation

// MARK: - Notification identifiers

enum TapeNotificationID {
    static let categoryMicActive = "TAPE_MIC_ACTIVE"
    static let actionRecord = "TAPE_RECORD"
    static let actionDismiss = "TAPE_DISMISS"
}

// MARK: - Output folder helpers

/// Returns the default tape output folder path (~/Documents/Tape), creating it if needed.
func tapeOutputFolder() -> String {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let tapePath = documents.appendingPathComponent("Tape")
    try? FileManager.default.createDirectory(at: tapePath, withIntermediateDirectories: true)
    return tapePath.path
}

/// Returns the user-configured output folder path, falling back to the default.
func resolvedOutputFolder() -> String {
    UserDefaults.standard.string(forKey: "outputFolderPath") ?? tapeOutputFolder()
}
