import Foundation

/// Manages ICS feed fetching, caching, and event lookup.
/// Refreshes every 5 minutes and on app launch.
/// Fires onEventStarting when a calendar event begins (±2 min window), once per event.
@MainActor
final class CalendarService: ObservableObject {
    @Published var upcomingEvents: [UpcomingMeeting] = []
    @Published var lastSynced: Date?
    @Published var syncError: String?

    /// Called when a calendar event starts. Use this as the primary recording trigger.
    var onEventStarting: ((UpcomingMeeting) -> Void)?

    private var refreshTimer: Timer?
    private var startCheckTimer: Timer?
    private var allEvents: [ICSParser.ParsedEvent] = []
    /// Tracks event start times already triggered this session to avoid double-firing
    private var triggeredEvents: Set<Date> = []

    func startPeriodicSync() {
        Task { await sync() }
        // Sync ICS data every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
        // Check for starting events every 60 seconds
        startCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkForStartingEvents() }
        }
    }

    func stopPeriodicSync() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        startCheckTimer?.invalidate()
        startCheckTimer = nil
    }

    /// Fires onEventStarting for any event whose start time is within a ±2 min window.
    /// Each event only triggers once per session.
    private func checkForStartingEvents() {
        guard onEventStarting != nil else { return }
        let now = Date()
        let window: TimeInterval = 2 * 60 // 2 minutes either side

        for event in allEvents {
            guard !triggeredEvents.contains(event.startDate) else { continue }
            let delta = now.timeIntervalSince(event.startDate)
            guard delta >= -window && delta <= window else { continue }

            triggeredEvents.insert(event.startDate)
            let meeting = UpcomingMeeting(
                title: event.summary,
                startDate: event.startDate,
                endDate: event.endDate
            )
            onEventStarting?(meeting)
        }
    }

    func sync() async {
        guard let urlString = KeychainService.load(key: "icsURL"),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            syncError = nil
            upcomingEvents = []
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let icsString = String(data: data, encoding: .utf8) else {
                syncError = "Could not decode ICS data"
                return
            }

            allEvents = ICSParser.parse(icsString)
            lastSynced = Date()
            syncError = nil
            updateUpcoming()
            checkForStartingEvents()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Find a calendar event matching a given time within a ±15 minute window.
    /// Returns the event that started most recently (handles overlaps).
    func matchEvent(at date: Date) -> UpcomingMeeting? {
        let window: TimeInterval = 15 * 60 // 15 minutes

        let matches = allEvents.filter { event in
            let expandedStart = event.startDate.addingTimeInterval(-window)
            let expandedEnd = event.endDate.addingTimeInterval(window)
            return date >= expandedStart && date <= expandedEnd
        }

        // Prefer the event that started most recently
        guard let best = matches.max(by: { $0.startDate < $1.startDate }) else {
            return nil
        }

        return UpcomingMeeting(
            title: best.summary,
            startDate: best.startDate,
            endDate: best.endDate
        )
    }

    private func updateUpcoming() {
        let now = Date()
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now)!

        upcomingEvents = allEvents
            .filter { $0.endDate >= now && $0.startDate <= weekFromNow }
            .sorted { $0.startDate < $1.startDate }
            .map { UpcomingMeeting(title: $0.summary, startDate: $0.startDate, endDate: $0.endDate) }
    }
}
