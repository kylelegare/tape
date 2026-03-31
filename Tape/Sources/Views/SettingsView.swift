import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            RecordingSettingsTab()
                .tabItem { Label("Recording", systemImage: "waveform") }

            CalendarSettingsTab()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            VocabularySettingsTab()
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
        }
        .frame(width: 450, height: 350)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("outputFolderPath") private var outputFolderPath: String = defaultOutputFolder()
    @AppStorage("launchAtLogin") private var launchAtLogin = false

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
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
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

    static func defaultOutputFolder() -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tapePath = documentsPath.appendingPathComponent("Tape")
        try? FileManager.default.createDirectory(at: tapePath, withIntermediateDirectories: true)
        return tapePath.path
    }
}

// MARK: - Recording

struct RecordingSettingsTab: View {
    @AppStorage("userName") private var userName = ""
    @AppStorage("whisperModel") private var whisperModel = "base"
    @AppStorage("minimumDuration") private var minimumDuration = 5
    @AppStorage("graceWindowDuration") private var graceWindowDuration = 30

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

                Stepper("Minimum recording: \(minimumDuration)s", value: $minimumDuration, in: 5...300, step: 5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Grace window")
                        Spacer()
                        Text(graceWindowDuration == 0 ? "off" : "\(graceWindowDuration)s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(graceWindowDuration) },
                        set: { graceWindowDuration = Int($0) }
                    ), in: 0...60, step: 5)
                }
                .help("Seconds to wait after meeting ends before finalizing. Set to 0 to stop immediately.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Calendar

struct CalendarSettingsTab: View {
    @State private var icsURL = ""
    @State private var lastSynced: Date?

    var body: some View {
        Form {
            Section("ICS Feed") {
                TextField("ICS Feed URL", text: $icsURL, prompt: Text("https://calendar.google.com/..."))
                    .onAppear { loadICSURL() }

                if let lastSynced {
                    Text("Last synced: \(lastSynced.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Save") { saveICSURL() }
                    Button("Sync Now") { syncCalendar() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func loadICSURL() {
        icsURL = KeychainService.load(key: "icsURL") ?? ""
    }

    private func saveICSURL() {
        KeychainService.save(key: "icsURL", value: icsURL)
    }

    private func syncCalendar() {
        NotificationCenter.default.post(name: .syncCalendar, object: nil)
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

#Preview {
    SettingsView()
}
