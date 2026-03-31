# Tape — Product Specification
**Version:** 1.0  
**Platform:** macOS (Sequoia 15+)  
**Stack:** Swift + SwiftUI, native macOS app  
**Build tool:** XcodeBuildMCP + Claude Code  

---

## What Tape Is

Tape is a lightweight macOS menu bar app that automatically captures meeting audio and outputs a structured `.md` file. No AI summaries. No editor. No cloud. Just audio in, transcript out — formatted for agent consumption.

The core loop:
1. Any app grabs the mic → Tape starts recording automatically
2. Call ends → Tape transcribes locally via Whisper
3. A structured `.md` file drops into a folder
4. Optionally: open the meeting in Tape, add a quick context note

That's it.

---

## Architecture

- **UI:** SwiftUI menu bar app — no Dock icon, no full window. Menu bar icon + popover for quick view. Separate panel window for meeting detail.
- **Audio capture:** `ScreenCaptureKit` for system audio (what others say) + `AVAudioEngine` for mic input (your side). Mixed into a single recording. No virtual audio drivers required. Requires macOS 13+.
- **Transcription:** `whisper.cpp` bundled with the app. Model downloaded on first launch (not bundled — too large). Default model: `medium`. Configurable in settings.
- **Speaker diarization:** On by default. Output as `Kyle:` / `Speaker 2:` / `Speaker 3:`. User's name configured in settings.
- **Calendar:** ICS/iCal feed URL. Fetched on a schedule (every 5 minutes). Parsed locally. URL stored in macOS Keychain — never written to disk or any config file.
- **Storage:** No database. Source of truth is always the `.md` files in the output folder. App reads the folder to populate the Previous Meetings list.
- **Output folder:** User-configured via folder picker in settings. Tape watches this folder to populate the UI.

---

## UI Layout

### Menu Bar Icon
- Tape icon in menu bar
- Click → opens main popover
- States:
  - Idle: static icon
  - Recording: subtle red dot indicator on icon
  - Transcribing: subtle spinner on icon

### Main Popover (click menu bar icon)
Three sections, top to bottom:

**1. Upcoming Meetings**
- Pulled from ICS feed
- Shows today + next 7 days
- Each row: `[time] [meeting title] [Start button]`
- If a meeting is currently recording, that row is highlighted with a live indicator
- If no ICS URL configured, shows "Add calendar in Settings →"

**2. Previous Meetings**
- List of completed `.md` files from output folder, sorted newest first
- Each row: `[date] [meeting title] [duration]`
- Click a row → opens Meeting Detail panel

**3. Bottom Bar — Recording Status**
- Hidden when idle
- When recording: `● Recording — [Meeting Title]  00:14:32  [Stop]`
- When transcribing: `⟳ Transcribing — [Meeting Title]`
- When done: `✓ Saved — [Meeting Title]` (disappears after 3 seconds)

**Footer:** `[Settings]` link, subtle

---

### Meeting Detail Panel
Opens as a separate floating panel (not a sheet) when clicking a previous meeting.

Layout:
```
[Meeting Title]                    [date / time / duration / source]

─── Context ────────────────────────────────────────────────────────
[Editable plain text field — no formatting, just a text area]
[Placeholder: "Add context for agents consuming this transcript..."]
                                                          [Save]

─── Transcript ─────────────────────────────────────────────────────
[Read-only, monospace, scrollable]
Kyle: So tell me what prompted the conversation today...
Speaker 2: Yeah so we've been looking at...
```

- Context block is the only editable part
- Saving rewrites only the `## Context` block in the `.md` file — transcript is never touched
- Transcript is read-only and not selectable for editing (selectable for copy is fine)

---

## Auto-Trigger Logic

Poll every 5 seconds using `AVCaptureDevice` to detect any app actively using the microphone.

When mic grab detected:
1. Start recording (mic + system audio simultaneously)
2. Try to match current time to a calendar event (±15 minute window)
3. If match found → use calendar event title as meeting title
4. If no match → use triggering app name + timestamp (e.g. `Zoom — Mar 30 2:04 PM`)
5. Update menu bar icon and recording status bar

When mic releases:
1. Stop recording
2. Begin transcription (whisper.cpp, selected model)
3. Run post-processing: find/replace custom vocabulary list
4. Write `.md` file to output folder
5. Refresh Previous Meetings list
6. Show `✓ Saved` toast

**Edge cases:**
- Minimum recording duration: 60 seconds. Discard anything shorter (prevents phantom recordings from Siri, browser mic grabs, etc.)
- If laptop closes mid-call: transcribe whatever was captured, write partial `.md` with a `partial: true` flag in frontmatter
- Overlapping calendar events: prefer the event that started most recently

---

## Output — `.md` File Format

**Filename:** `YYYY-MM-DD-meeting-title-slugified.md`  
Example: `2026-03-30-acme-corp-discovery-call.md`

**Contents:**
```markdown
---
title: Acme Corp - Discovery Call
date: 2026-03-30
time: 14:00 PST
duration: 43min
source: Zoom
speakers:
  - Kyle
  - Speaker 2
partial: false
---

## Context

[Empty by default. User adds notes here via Tape's detail panel.]

## Transcript

**Kyle:** So tell me what prompted the conversation today...

**Speaker 2:** Yeah so we've been looking at a few solutions...

**Kyle:** What's driving the timeline?
```

Notes:
- `## Context` block is always present even if empty — agents should check it
- `partial: true` if recording was cut short
- `source` is the name of the app that triggered recording (e.g. Zoom, Slack, FaceTime)
- Speakers: user's configured name for their mic, `Speaker 2` / `Speaker 3` for others
- Transcript uses `**Name:**` markdown bold formatting for speaker labels

---

## Custom Vocabulary

Two-layer approach:
1. **Whisper initial prompt:** Custom words passed to whisper.cpp before transcription to bias recognition
2. **Post-processing find/replace:** After transcription, deterministic cleanup pass

Both use the same word list from Settings. User enters correct forms (e.g. `Glia`, `MEDDPICC`, `Digital One Chat`). Tape handles the rest automatically.

---

## Settings Panel

Simple preferences window. Sections:

**Calendar**
- ICS Feed URL (text field) — stored in Keychain
- Last synced: [timestamp]
- [Sync Now] button

**Recording**
- Your name (used for speaker labeling) — default: empty, shows as `Speaker 1`
- Whisper model: [Tiny / Base / Small / Medium / Large-v3] — default: Medium
- Minimum recording duration before saving: [60 seconds] (stepper)

**Output**
- Output folder: [folder picker] — default: `~/Documents/Tape/`

**Custom Vocabulary**
- Plain list, one word/phrase per line
- Correct forms only (e.g. `Glia`, `MEDDPICC`)
- [+ Add] button, deletable rows

**General**
- Launch at login: [toggle]
- [Opt out of XcodeBuildMCP telemetry if applicable]

---

## What Tape Is NOT

- No AI summary
- No notepad or editor
- No cloud sync or accounts
- No database — `.md` files are the database
- No transcript viewer beyond the detail panel's read-only view
- No bot joining your calls
- No modification of transcripts after save (context note only)

---

## Reference Repos (for audio capture implementation)

- **Char** (fastrepl/char) — MIT licensed, native Swift, ScreenCaptureKit audio capture
- **RecapAI/Recap** — Open source, Core Audio Taps + AVAudioEngine, meeting auto-detection
- **Azayaka** (Mnpn/Azayaka) — Small macOS menu bar app, ScreenCaptureKit system audio

Use these as reference for the audio capture layer specifically. Do not adopt their broader architecture, database patterns, or AI summary features.
