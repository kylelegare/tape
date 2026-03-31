import Foundation

struct Meeting: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let duration: TimeInterval?
    let source: String?
    let partial: Bool
    let filePath: URL?
}

struct UpcomingMeeting: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
}
