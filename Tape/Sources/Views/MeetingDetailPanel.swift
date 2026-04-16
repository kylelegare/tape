import SwiftUI

/// Floating panel window for viewing a meeting transcript and editing context.
struct MeetingDetailView: View {
    let meeting: Meeting
    let store: MeetingStore

    @State private var editableTitle: String = ""
    @State private var context: String = ""
    @State private var transcript: String = ""
    @State private var hasUnsavedChanges = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            contextSection
            Divider()
            transcriptSection
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 600)
        .onAppear {
            editableTitle = meeting.title
            context = store.readContext(for: meeting)
            transcript = store.readTranscript(for: meeting)
            // Reset after initial state assignment so onChange doesn't show a phantom Save button
            DispatchQueue.main.async { hasUnsavedChanges = false }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $editableTitle)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .focused($titleFocused)
                    .onSubmit { saveTitle() }
                    .onChange(of: titleFocused) {
                        if !titleFocused { saveTitle() }
                    }

                HStack(spacing: 12) {
                    Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                    if let duration = meeting.duration {
                        Text("\(Int(duration / 60))min")
                    }
                    if meeting.partial {
                        Text("Partial")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private func saveTitle() {
        let trimmed = editableTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != meeting.title else { return }
        store.rename(meeting, to: trimmed)
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasUnsavedChanges {
                    Button("Save") {
                        store.saveContext(for: meeting, context: context)
                        hasUnsavedChanges = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            TextEditor(text: $context)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(.horizontal, 12)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .onChange(of: context) {
                    hasUnsavedChanges = true
                }

            if context.isEmpty {
                Text("Add context for agents consuming this transcript...")
                    .foregroundStyle(.tertiary)
                    .font(.body)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView {
                Text(transcript)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Retains open detail panels so they aren't released while visible.
private var openDetailPanels: [NSPanel] = []

/// Opens a meeting detail as a floating panel window
@MainActor
func openMeetingDetailPanel(meeting: Meeting, store: MeetingStore) {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
        styleMask: [.titled, .closable, .resizable, .utilityWindow],
        backing: .buffered,
        defer: false
    )
    panel.title = meeting.title
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = false
    panel.isReleasedWhenClosed = false
    panel.contentView = NSHostingView(rootView: MeetingDetailView(meeting: meeting, store: store))
    panel.center()
    panel.makeKeyAndOrderFront(nil)

    openDetailPanels.append(panel)

    // Capture token so it can be removed on close — prevents accumulating dead observers.
    // Stored in a class wrapper so the closure can reference it without a mutability warning.
    final class TokenBox: @unchecked Sendable { var value: NSObjectProtocol? }
    let box = TokenBox()
    box.value = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: panel,
        queue: .main
    ) { [weak panel] _ in
        openDetailPanels.removeAll { $0 === panel }
        if let t = box.value { NotificationCenter.default.removeObserver(t) }
    }
}
