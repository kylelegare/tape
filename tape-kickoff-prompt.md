# Tape — Claude Code Kickoff Prompt

Paste this into Claude Code to start the build. Run from your project directory.

---

## Prompt

You are building **Tape** — a lightweight native macOS app (Swift + SwiftUI) that automatically captures meeting audio and outputs structured `.md` files for agent consumption. Full spec is in `tape-spec.md` in this directory. Read it before writing any code.

Your job is to scaffold the full Xcode project and implement the app iteratively. Use XcodeBuildMCP to build and verify after each major step.

---

### Build Order

Work through these phases in order. Build and verify each phase before moving to the next.

**Phase 1 — Project scaffold**
- Create a new macOS Xcode project named `Tape`
- Configure as menu bar app: `LSUIElement = true` in Info.plist (no Dock icon)
- Set deployment target: macOS 13.0 (Ventura) minimum
- Add required entitlements:
  - `com.apple.security.device.audio-input` (microphone)
  - `com.apple.security.screen-capture` (ScreenCaptureKit system audio)
- Verify it builds and launches showing a menu bar icon

**Phase 2 — Menu bar icon + popover shell**
- Menu bar icon using SF Symbols (`record.circle` or similar)
- Click → opens SwiftUI popover
- Popover has three placeholder sections: Upcoming, Previous, Status bar
- No functionality yet, just the layout shell
- Build and verify popover opens on click

**Phase 3 — Settings panel**
- Preferences window (standard macOS, `⌘,`)
- Fields: ICS URL (stored in Keychain via `SecItemAdd`), Your Name, Output Folder picker, Whisper Model picker, Minimum Duration stepper, Custom Vocabulary list, Launch at Login toggle
- ICS URL must never be written to UserDefaults or any file — Keychain only
- Build and verify settings open and persist across launches

**Phase 4 — ICS calendar feed**
- Fetch ICS URL from Keychain
- Parse `.ics` format: extract VEVENT blocks, pull DTSTART, DTEND, SUMMARY fields
- Handle timezone offsets
- Refresh every 5 minutes, and on app launch
- Populate Upcoming section in popover: today + next 7 days, sorted by time
- Build and verify with a real ICS URL

**Phase 5 — Audio capture**
- Implement mic capture via `AVAudioEngine`
- Implement system audio capture via `ScreenCaptureKit` (macOS 13+)
- Mix both streams into a single recording
- Reference: fastrepl/char and RecapAI/Recap on GitHub for the ScreenCaptureKit implementation pattern
- Do NOT use BlackHole or any virtual audio driver
- Save raw audio to a temp file during recording
- Build and verify both audio streams are captured (test by recording and playing back)

**Phase 6 — Auto-trigger (mic watcher)**
- Poll every 5 seconds using `AVCaptureDevice.default(for: .audio)` and check `isInUseByAnotherApplication`
- When mic grab detected → start recording
- Match start time to calendar events (±15 minute window) for title
- Fallback title: `[App Name] — [Date Time]` (detect triggering app via `NSWorkspace.shared.frontmostApplication`)
- When mic releases → stop recording
- Enforce minimum duration (from settings, default 60s): discard if shorter
- Update menu bar icon state: idle / recording (red dot) / transcribing (spinner)
- Build and verify auto-trigger fires when opening Zoom or FaceTime

**Phase 7 — Whisper transcription**
- Integrate `whisper.cpp` via Swift Package Manager or as a compiled binary
- On first launch, if no model present: download selected model from HuggingFace/OpenAI CDN to `~/Library/Application Support/Tape/models/`
- Show download progress in status bar
- Run transcription on the temp audio file after recording stops
- Enable speaker diarization — output as `Kyle:` / `Speaker 2:` (use configured name for mic speaker)
- Build and verify a test recording transcribes correctly

**Phase 8 — Custom vocabulary**
- Pass custom vocabulary list as `initial_prompt` to whisper.cpp before transcription
- After transcription completes, run find/replace pass: for each word in vocabulary list, replace case-insensitive matches with the correct form
- Build and verify a word like "glia" becomes "Glia" in output

**Phase 9 — `.md` file output**
- After transcription + vocabulary cleanup, write `.md` file to output folder
- Filename: `YYYY-MM-DD-title-slugified.md`
- Format exactly as specified in tape-spec.md
- `## Context` block always present, empty by default
- `partial: true` in frontmatter if recording was interrupted
- Refresh Previous Meetings list after file is written
- Show `✓ Saved — [Title]` in status bar for 3 seconds
- Build and verify a complete `.md` appears in the output folder after a test call

**Phase 10 — Previous meetings list + detail panel**
- Read output folder to populate Previous Meetings list (sorted newest first)
- Each row: date, title, duration (from frontmatter)
- Click row → open Meeting Detail panel (floating NSPanel, not a sheet)
- Panel layout: metadata header, editable Context text area, read-only Transcript
- Save button rewrites only the `## Context` block in the `.md` file
- Transcript block is read-only (copy OK, no editing)
- Build and verify end-to-end: record → transcribe → see in list → add context note → check file

---

### Code Standards

- Swift 5.9+, SwiftUI for all UI
- No third-party UI frameworks
- Async/await for all async operations
- Proper error handling — never crash silently, show user-facing error in status bar if something fails
- No hardcoded paths — always use `FileManager` and proper app support directories
- Comments on anything non-obvious, especially the audio capture code

### What NOT to build
- No AI summary
- No notepad or text editor
- No database (SQLite or otherwise) — `.md` files are the source of truth
- No cloud features, accounts, or networking beyond ICS fetch and model download
- No modification of transcript content after save

### Key references (check GitHub for audio capture patterns)
- `fastrepl/char` — ScreenCaptureKit audio in Swift
- `RecapAI/Recap` — Core Audio Taps + AVAudioEngine
- `Mnpn/Azayaka` — Menu bar + ScreenCaptureKit

Start with Phase 1. Read tape-spec.md fully first. Ask if anything is ambiguous before writing code.
