import Foundation

/// Reads the output folder to populate the Previous Meetings list.
/// Parses frontmatter from .md files. The folder is the source of truth.
@MainActor
final class MeetingStore: ObservableObject {
    @Published var meetings: [Meeting] = []

    private var folderWatcher: DispatchSourceFileSystemObject?
    private var outputFolderObserver: NSObjectProtocol?

    func loadMeetings() {
        let outputDir = URL(fileURLWithPath: resolvedOutputFolder())

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: outputDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            meetings = []
            return
        }

        meetings = files
            .filter { $0.pathExtension == "md" }
            .compactMap { parseMeetingFile(at: $0) }
            .sorted { ($0.date) > ($1.date) }
    }

    func startWatching() {
        loadMeetings()
        armFolderSource()

        // Re-arm whenever the output folder path changes in Settings
        outputFolderObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.armFolderSource() }
        }
    }

    func stopWatching() {
        folderWatcher?.cancel()
        folderWatcher = nil
        if let obs = outputFolderObserver {
            NotificationCenter.default.removeObserver(obs)
            outputFolderObserver = nil
        }
    }

    private func armFolderSource() {
        // Cancel existing source first to prevent fd leaks when re-arming
        folderWatcher?.cancel()
        folderWatcher = nil
        loadMeetings()

        let outputPath = resolvedOutputFolder()
        let fd = open(outputPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.loadMeetings()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        folderWatcher = source
    }

    // MARK: - Frontmatter Parsing

    private func parseMeetingFile(at url: URL) -> Meeting? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let frontmatter = parseFrontmatter(content)
        guard let title = frontmatter["title"] else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = frontmatter["date"].flatMap { dateFormatter.date(from: $0) } ?? Date()

        let duration: TimeInterval? = frontmatter["duration"]
            .flatMap { str in
                // Parse "43min" format
                let digits = str.filter(\.isNumber)
                return Double(digits).map { $0 * 60 }
            }

        let partial = frontmatter["partial"] == "true"
        let source = frontmatter["source"]

        return Meeting(
            title: title,
            date: date,
            duration: duration,
            source: source,
            partial: partial,
            filePath: url
        )
    }

    private func parseFrontmatter(_ content: String) -> [String: String] {
        let lines = content.components(separatedBy: "\n")
        var result: [String: String] = [:]
        var inFrontmatter = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if inFrontmatter { break } // end of frontmatter
                inFrontmatter = true
                continue
            }
            if inFrontmatter, let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.hasPrefix("-") { // skip YAML array items
                    result[key] = value
                }
            }
        }

        return result
    }

    // MARK: - Rename

    /// Update the title in the meeting's .md frontmatter. Folder watcher reloads automatically.
    func rename(_ meeting: Meeting, to newTitle: String) {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty,
              let path = meeting.filePath,
              let content = try? String(contentsOf: path, encoding: .utf8)
        else { return }

        let updated = content
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("title:") ? "title: \(newTitle)" : line
            }
            .joined(separator: "\n")

        try? updated.write(to: path, atomically: true, encoding: .utf8)
        loadMeetings() // folder watcher only fires on directory changes, not file writes
    }

    // MARK: - Context Editing

    /// Read the context section from a meeting's .md file
    func readContext(for meeting: Meeting) -> String {
        guard let path = meeting.filePath,
              let content = try? String(contentsOf: path, encoding: .utf8)
        else { return "" }

        return extractContextBlock(from: content)
    }

    /// Save updated context to the meeting's .md file (only rewrites ## Context block)
    func saveContext(for meeting: Meeting, context: String) {
        guard let path = meeting.filePath,
              var content = try? String(contentsOf: path, encoding: .utf8)
        else { return }

        content = replaceContextBlock(in: content, with: context)
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Read the transcript section from a meeting's .md file
    func readTranscript(for meeting: Meeting) -> String {
        guard let path = meeting.filePath,
              let content = try? String(contentsOf: path, encoding: .utf8)
        else { return "" }

        return extractTranscriptBlock(from: content)
    }

    private func extractContextBlock(from content: String) -> String {
        guard let contextStart = content.range(of: "## Context\n") else { return "" }
        let afterContext = content[contextStart.upperBound...]

        if let transcriptStart = afterContext.range(of: "## Transcript") {
            return String(afterContext[..<transcriptStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(afterContext).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTranscriptBlock(from content: String) -> String {
        guard let transcriptStart = content.range(of: "## Transcript\n") else { return "" }
        return String(content[transcriptStart.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replaceContextBlock(in content: String, with newContext: String) -> String {
        guard let contextStart = content.range(of: "## Context\n") else { return content }
        let beforeContext = content[..<contextStart.upperBound]
        let afterContext = content[contextStart.upperBound...]

        if let transcriptStart = afterContext.range(of: "## Transcript") {
            return String(beforeContext) + "\n" + newContext + "\n\n" + String(afterContext[transcriptStart.lowerBound...])
        }
        return String(beforeContext) + "\n" + newContext + "\n"
    }
}
