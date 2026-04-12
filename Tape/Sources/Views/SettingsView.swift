import SwiftUI

struct SettingsView: View {
    let allowlist: MicAllowlist

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            RecordingSettingsTab()
                .tabItem { Label("Recording", systemImage: "waveform") }

            VocabularySettingsTab()
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }

            DetectionSettingsTab(allowlist: allowlist)
                .tabItem { Label("Detection", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 450, height: 420)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("outputFolderPath") private var outputFolderPath: String = tapeOutputFolder()
    @StateObject private var launchManager = LaunchAtLoginManager.shared

    var body: some View {
        Form {
            Section("Output") {
                HStack {
                    TextField("Output folder", text: .constant(outputFolderPath))
                        .disabled(true)
                    Button("Choose...") {
                        chooseOutputFolder()
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setEnabled($0) }
                ))

                if let statusMessage = launchManager.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchManager.refresh()
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            outputFolderPath = url.path
        }
    }

}

// MARK: - Recording

struct RecordingSettingsTab: View {
    @AppStorage("userName") private var userName = ""
    @AppStorage("whisperModel") private var whisperModel = "tiny"
    @AppStorage("minimumDuration") private var minimumDuration = 5

    private let modelOptions = ["tiny", "base", "small", "medium", "large-v3"]

    var body: some View {
        Form {
            Section("Speaker") {
                TextField("Your name", text: $userName, prompt: Text("Used for speaker labeling"))
            }

            Section("Transcription") {
                Picker("Whisper model", selection: $whisperModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model.capitalized).tag(model)
                    }
                }
                .help("Models download on first use and are stored locally in Application Support.")

                Stepper("Minimum recording: \(minimumDuration)s", value: $minimumDuration, in: 5...300, step: 5)

                Text("Models download on first transcription and stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Vocabulary

struct VocabularySettingsTab: View {
    @AppStorage("customVocabulary") private var customVocabularyJSON: String = "[]"
    @State private var words: [String] = []
    @State private var newWord = ""

    var body: some View {
        Form {
            Section("Custom Vocabulary") {
                Text("Enter correct forms. tape uses these to bias transcription and fix common misrecognitions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Add word or phrase", text: $newWord)
                        .onSubmit { addWord() }
                    Button("Add") { addWord() }
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !words.isEmpty {
                    List {
                        ForEach(words, id: \.self) { word in
                            Text(word)
                        }
                        .onDelete { indices in
                            words.remove(atOffsets: indices)
                            saveWords()
                        }
                    }
                    .frame(minHeight: 100)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadWords() }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        words.append(trimmed)
        newWord = ""
        saveWords()
    }

    private func loadWords() {
        if let data = customVocabularyJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            words = decoded
        }
    }

    private func saveWords() {
        if let data = try? JSONEncoder().encode(words),
           let json = String(data: data, encoding: .utf8) {
            customVocabularyJSON = json
        }
    }
}

// MARK: - Detection

struct DetectionSettingsTab: View {
    @ObservedObject var allowlist: MicAllowlist

    var body: some View {
        Form {
            Section("Meeting apps") {
                ForEach(allowlist.defaultAppEntries) { entry in
                    AppToggleRow(
                        entry: entry,
                        isEnabled: allowlist.isEnabled(entry.bundleID),
                        onToggle: { allowlist.toggle(entry.bundleID) }
                    )
                }
            }

            if !allowlist.discoveredApps.isEmpty {
                Section("Also detected on this Mac") {
                    ForEach(allowlist.discoveredApps) { entry in
                        AppToggleRow(
                            entry: entry,
                            isEnabled: allowlist.isEnabled(entry.bundleID),
                            onToggle: { allowlist.toggle(entry.bundleID) }
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AppToggleRow: View {
    let entry: AppEntry
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isEnabled }, set: { _ in onToggle() })) {
            HStack(spacing: 8) {
                if let icon = entry.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(entry.displayName)
            }
        }
    }
}

#Preview {
    SettingsView(allowlist: MicAllowlist())
}
