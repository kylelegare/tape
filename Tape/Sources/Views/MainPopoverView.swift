import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var meetingStore: MeetingStore

    var body: some View {
        VStack(spacing: 0) {
            UpcomingMeetingsSection(events: calendarService.upcomingEvents)

            Divider()

            PreviousMeetingsSection(meetings: meetingStore.meetings, store: meetingStore)

            Divider()

            BottomBar(recordingManager: recordingManager)
        }
        .frame(width: 340, height: 480)
    }
}

// MARK: - Upcoming Meetings

struct UpcomingMeetingsSection: View {
    let events: [UpcomingMeeting]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Upcoming")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if events.isEmpty {
                Text("Add calendar in Settings")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(events) { event in
                            UpcomingMeetingRow(event: event)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 180)
            }
        }
    }
}

struct UpcomingMeetingRow: View {
    let event: UpcomingMeeting

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }
}

// MARK: - Previous Meetings

struct PreviousMeetingsSection: View {
    let meetings: [Meeting]
    let store: MeetingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Previous")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if meetings.isEmpty {
                ScrollView {
                    Text("No recordings yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(meetings) { meeting in
                            PreviousMeetingRow(meeting: meeting, store: store)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct PreviousMeetingRow: View {
    let meeting: Meeting
    let store: MeetingStore

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isRenaming {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .focused($renameFocused)
                            .onSubmit { commitRename() }
                            .onExitCommand { isRenaming = false }
                    } else {
                        Text(meeting.title)
                            .font(.subheadline)
                            .lineLimit(1)
                            .onTapGesture { startRenaming() }
                    }
                    if meeting.partial {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 8) {
                    Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                    if let duration = meeting.duration {
                        Text("\(Int(duration / 60))min")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openMeetingDetailPanel(meeting: meeting, store: store)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
        .contentShape(Rectangle())
        .onTapGesture {
            openMeetingDetailPanel(meeting: meeting, store: store)
        }
    }

    private func startRenaming() {
        renameText = meeting.title
        isRenaming = true
        renameFocused = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { store.rename(meeting, to: trimmed) }
        isRenaming = false
    }
}

// MARK: - Bottom Bar

/// Unified toolbar + status. Replaces the old split RecordingStatusBar / FooterBar.
/// Layout: status row (when active) + icon toolbar [folder | record/stop | settings]
struct BottomBar: View {
    @ObservedObject var recordingManager: RecordingManager

    var body: some View {
        VStack(spacing: 0) {
            // Status row — only shown when there's something to report
            if showStatusRow {
                statusRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                Divider()
            }

            // Icon toolbar
            HStack(spacing: 0) {
                // Open recordings folder
                Button {
                    openOutputFolder()
                } label: {
                    Image(systemName: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open recordings folder in Finder")

                Divider().frame(height: 16)

                // Record / Stop
                Group {
                    if recordingManager.state == .recording {
                        Button {
                            recordingManager.stopRecording()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "stop.circle")
                                Text("Stop")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .foregroundStyle(.red)
                    } else {
                        Button {
                            recordingManager.startOneOffRecording()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "record.circle")
                                Text("Record")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .foregroundStyle(.secondary)
                        .disabled(recordingManager.state == .transcribing)
                    }
                }
                .buttonStyle(.plain)

                Divider().frame(height: 16)

                // Settings
                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
            }
            .font(.system(size: 13))
            .padding(.vertical, 10)
        }
    }

    private var showStatusRow: Bool {
        recordingManager.state != .idle || recordingManager.statusMessage != nil
    }

    @ViewBuilder
    private var statusRow: some View {
        switch recordingManager.state {
        case .idle:
            if let message = recordingManager.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(message).lineLimit(1)
                    Spacer()
                }
                .font(.caption)
            }
        case .recording:
            HStack(spacing: 6) {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text("\(recordingManager.currentMeetingTitle ?? "recording") — \(formattedDuration)")
                    .lineLimit(1)
                Spacer()
            }
            .font(.caption)
        case .transcribing:
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                Text(recordingManager.statusMessage ?? "transcribing…").lineLimit(1)
                Spacer()
            }
            .font(.caption)
        }
    }

    private var formattedDuration: String {
        let total = Int(recordingManager.recordingDuration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func openOutputFolder() {
        let path = UserDefaults.standard.string(forKey: "outputFolderPath")
            ?? GeneralSettingsTab.defaultOutputFolder()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let syncCalendar = Notification.Name("syncCalendar")
}
