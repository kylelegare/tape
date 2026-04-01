import XCTest
@testable import Tape

@MainActor
final class MeetingStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var originalOutputFolder: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        originalOutputFolder = UserDefaults.standard.string(forKey: "outputFolderPath")
        UserDefaults.standard.set(tempDirectory.path, forKey: "outputFolderPath")
    }

    override func tearDownWithError() throws {
        if let originalOutputFolder {
            UserDefaults.standard.set(originalOutputFolder, forKey: "outputFolderPath")
        } else {
            UserDefaults.standard.removeObject(forKey: "outputFolderPath")
        }

        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testLoadMeetingsParsesQuotedTitleDurationAndPartial() throws {
        let fileURL = tempDirectory.appendingPathComponent("2026-03-31-sync.md")
        try meetingMarkdown(
            title: "\"Weekly Sync: Core\"",
            duration: "47min",
            partial: true,
            context: "Roadmap review",
            transcript: "**Kyle:** Ship it"
        ).write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MeetingStore()
        store.loadMeetings()

        XCTAssertEqual(store.meetings.count, 1)
        XCTAssertEqual(store.meetings[0].title, "Weekly Sync: Core")
        XCTAssertEqual(store.meetings[0].duration, 47 * 60)
        XCTAssertEqual(store.meetings[0].partial, true)
        XCTAssertEqual(store.meetings[0].source, "Zoom")
    }

    func testRenameQuotesTitlesWithColons() throws {
        let fileURL = tempDirectory.appendingPathComponent("2026-03-31-sync.md")
        try meetingMarkdown(
            title: "Weekly Sync",
            duration: "12min",
            partial: false,
            context: "",
            transcript: "Hello"
        ).write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MeetingStore()
        let meeting = Meeting(
            title: "Weekly Sync",
            date: Date(),
            duration: 12 * 60,
            source: "Zoom",
            partial: false,
            filePath: fileURL
        )

        store.rename(meeting, to: "Roadmap: Q2")

        let updated = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("title: \"Roadmap: Q2\""))
    }

    func testSaveContextOnlyReplacesContextBlock() throws {
        let fileURL = tempDirectory.appendingPathComponent("2026-03-31-sync.md")
        try meetingMarkdown(
            title: "Weekly Sync",
            duration: "12min",
            partial: false,
            context: "Old context",
            transcript: "**Kyle:** Hello"
        ).write(to: fileURL, atomically: true, encoding: .utf8)

        let store = MeetingStore()
        let meeting = Meeting(
            title: "Weekly Sync",
            date: Date(),
            duration: 12 * 60,
            source: "Zoom",
            partial: false,
            filePath: fileURL
        )

        store.saveContext(for: meeting, context: "New context\n- action item")

        XCTAssertEqual(store.readContext(for: meeting), "New context\n- action item")
        XCTAssertEqual(store.readTranscript(for: meeting), "**Kyle:** Hello")
    }

    private func meetingMarkdown(
        title: String,
        duration: String,
        partial: Bool,
        context: String,
        transcript: String
    ) -> String {
        """
        ---
        title: \(title)
        date: 2026-03-31
        time: 14:00
        duration: \(duration)
        source: Zoom
        speakers:
          - Kyle
          - Speaker 2
        partial: \(partial)
        ---

        ## Context

        \(context)

        ## Transcript

        \(transcript)
        """
    }
}
