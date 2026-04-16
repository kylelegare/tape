import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var meetingStore: MeetingStore

    var body: some View {
        VStack(spacing: 0) {
            RecordHero(recordingManager: recordingManager)

            Divider()

            RecordingsList(meetings: meetingStore.meetings, store: meetingStore)

            Divider()

            MiniFooter()
        }
        .frame(width: 320, height: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Record Hero

/// Top section — the primary action. Shows Record button when idle,
/// live status + Stop when recording.
struct RecordHero: View {
    @ObservedObject var recordingManager: RecordingManager

    var body: some View {
        Group {
            switch recordingManager.state {
            case .idle:
                idleView
            case .recording:
                recordingView
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Button {
                recordingManager.beginRecording()
            } label: {
                Label("Record", systemImage: "record.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)

            if let msg = recordingManager.statusMessage {
                HStack(spacing: 6) {
                    if recordingManager.isTranscribing {
                        ProgressView().scaleEffect(0.7).controlSize(.small)
                    }
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var recordingView: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording")
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button("Stop") {
                recordingManager.stopRecording()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var formattedDuration: String {
        let total = Int(recordingManager.recordingDuration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Recordings List

struct RecordingsList: View {
    let meetings: [Meeting]
    let store: MeetingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recordings")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if meetings.isEmpty {
                Text("No recordings yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(meetings) { meeting in
                            RecordingRow(meeting: meeting, store: store)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct RecordingRow: View {
    let meeting: Meeting
    let store: MeetingStore

    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
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
                HStack(spacing: 6) {
                    Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                    if let duration = meeting.duration {
                        Text("\(Int(duration / 60))m")
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

// MARK: - Mini Footer

struct MiniFooter: View {
    var body: some View {
        HStack(spacing: 0) {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: resolvedOutputFolder()))
            } label: {
                Image(systemName: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open recordings folder")

            Divider().frame(height: 14)

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
        .padding(.vertical, 9)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
