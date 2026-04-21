import Foundation

struct Meeting: Identifiable {
    /// Stable identity derived from the backing file path so SwiftUI rows survive reloads.
    var id: String { filePath?.absoluteString ?? "\(title)-\(date.timeIntervalSince1970)" }
    let title: String
    let date: Date
    let duration: TimeInterval?
    let partial: Bool
    let filePath: URL?
}

