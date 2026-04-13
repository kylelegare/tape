---
date: 2026-04-13
topic: open-ideation
focus: open-ended — best improvements to Tape
---

# Ideation: Tape Open Improvements

## Codebase Context

Tape is a lightweight macOS menu bar app (Swift/SwiftUI, AppKit) that:
- Detects mic usage by meeting apps via CoreAudio process-level watching
- Records mic + system audio as separate CAF streams, mixes to .m4a
- Transcribes with SwiftWhisper (CPU) and writes Markdown to ~/Documents/tape/
- Has an allowlist of 16 meeting apps; toggleable per-app in Settings

**Active plan:** Migrate to WhisperKit (Core ML, built-in VAD) + dual-stream diarization
(`docs/plans/2026-04-13-001-feat-whisperkit-diarization-plan.md`)

**Known pains at time of ideation:**
1. Meeting titles are bad — auto-detection falls back to bare app name
2. Speaker labels all show as the user's name (fixed by WhisperKit plan)
3. Auto-mic detection can miss recordings on some machines (mic permission)
4. No visibility into the grace window countdown

**Constraints:**
- Lightweight — no servers, no cloud, no extra ML models beyond Whisper
- Local-first, on-device only
- Transcript fidelity over cleanup/summarization
- Kyle uses Tape for personal use; simplicity is a feature

---

## Ranked Ideas

### 1. Grace Window Countdown
**Description:** Show remaining seconds of the grace period in the menu bar icon (badge or icon swap) or in the popover, so the user knows how long until the recording auto-stops.
**Rationale:** Directly addresses a stated real pain with a UI-only change. The grace window task already exists in RecordingManager — surfacing its remaining time requires only a published property and a timer tick. No new subsystems.
**Downsides:** A ticking countdown visible in the menu bar may be distracting on screen-share. Consider suppressing the badge or making it subtle (e.g., pulsing icon instead of number).
**Confidence:** 97%
**Complexity:** Low
**Status:** Unexplored

---

### 2. Post-Recording Title Prompt
**Description:** After the recording stops (before transcription runs), show a small non-blocking prompt with the auto-detected title pre-filled. User can confirm, edit, or clear it. Saving proceeds with whatever they type.
**Rationale:** Directly compensates for the #1 stated pain (bad meeting titles) by letting the user correct at the moment it matters. Only requires a small NSPanel or popover overlay — no new state machine.
**Downsides:** Adds an interruption after every recording. Needs a visible "skip" path with a short timeout (e.g. 30s auto-confirm), otherwise it trains the user to always dismiss it and it becomes noise.
**Confidence:** 93%
**Complexity:** Low
**Status:** Unexplored

---

### 3. EventKit Calendar Integration
**Description:** At recording start, query EventKit for calendar events within ±15 minutes of the current time. If exactly one match exists, use its title as the meeting name. Falls back to the existing MeetingIdentity chain if none or multiple match.
**Rationale:** Fixes title quality at the source using on-device data. EventKit is a well-supported Apple framework, no network required. Integrates cleanly into MeetingIdentity.resolve() as a new first-pass layer before window-title detection.
**Downsides:** Requires an OS calendar permission dialog (another prompt). Generic event titles ("Sync", "Chat", "1:1") are common and produce poor titles just like the current fallback. Works best for people with well-titled calendars.
**Confidence:** 88%
**Complexity:** Medium
**Status:** Unexplored

---

### 4. Timestamps in Transcript
**Description:** Add [mm:ss] markers at each Whisper segment boundary in the saved Markdown transcript. WhisperKit (and current SwiftWhisper) already return per-segment start/end times — surfacing them costs nearly nothing.
**Rationale:** Makes transcripts directly navigable — "what were we talking about at 23 minutes?" becomes answerable without scrubbing audio. Segment timestamps are already available in the data model.
**Downsides:** Whisper segments are 5-30s chunks, so timestamp density is coarser than word-level. For a 90-minute meeting, this may still feel imprecise for fast lookups. Clutters the Markdown slightly.
**Confidence:** 87%
**Complexity:** Low
**Status:** Unexplored

---

### 5. Post-Write Shell Hook
**Description:** After the .md file is written, run a user-configured shell command with the file path as an argument. User sets it in Settings (a text field). Empty = no-op. Example: `cp "$TAPE_FILE" ~/Documents/Obsidian/Inbox/`
**Rationale:** A single shell hook is the minimal extensibility primitive that covers Obsidian sync, git commit, custom notification, Shortcuts integration, and any future workflow — without baking any specific integration into Tape. Zero overhead if unused.
**Downsides:** Shell injection risk if the filepath is interpolated naively. Requires careful quoting. Also: a misconfigured hook silently fails unless Tape surfaces the exit code somewhere.
**Confidence:** 85%
**Complexity:** Low
**Status:** Unexplored

---

### 6. Global Keyboard Shortcut
**Description:** Register a user-configurable global hotkey (e.g. ⌥⌘R) that starts or stops a one-off recording from any app without needing to click the menu bar icon.
**Rationale:** Reduces friction for manual recordings during screen-shares or full-screen apps where the menu bar is hidden. Standard macOS pattern via Carbon hotkeys or AppKit event tap.
**Downsides:** Global hotkeys conflict with other apps. The user must choose a chord that nothing else owns — which often requires a settings UI (combobox + conflict detection) that adds more surface than it first appears. Also: sandboxed apps may need an entitlement.
**Confidence:** 80%
**Complexity:** Low
**Status:** Unexplored

---

### 7. Inline App Toggles in Popover
**Description:** Surface the app allowlist toggle directly in the main popover as a compact secondary section, so users can quickly enable/disable an app they just noticed triggering without navigating to Settings.
**Rationale:** The allowlist data model is clean and already ObservableObject. This is a pure UI addition with no new data plumbing.
**Downsides:** The popover is already compact. Inline settings risk making it feel like a configuration panel rather than a lightweight status indicator. The Settings tab approach is the cleaner separation of concerns.
**Confidence:** 72%
**Complexity:** Low
**Status:** Unexplored

---

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | NaturalLanguage topic extraction | Summarization feature — violates transcript-fidelity constraint; NL framework mediocre for meeting vocabulary |
| 2 | Action item detection | Same as above — summarization, and NL sentence classifiers produce enough false positives the output can't be trusted without human review |
| 3 | Obsidian URI deep-link | Specific integration when the shell hook (idea #5) covers it more generally without polluting the Markdown |
| 4 | Tape:// URI scheme | Premature infrastructure for a personal-use tool; the shell hook covers the automation use case |
| 5 | Chunked/streaming transcription | Large architectural change to the Whisper pipeline with no stated latency pain; wrong problem |
| 6 | Silent-record mode | Removes the only friction point preventing accidental capture of sensitive conversations |
| 7 | Audio-as-primary-product (save m4a permanently) | Doubles storage footprint; transcript is the product; archiving audio is out of scope |
| 8 | Blocklist instead of allowlist | Over-triggering (voice dictation, games, music) is the original failure mode allowlist was built to prevent; switching flips the failure mode |
| 9 | Mid-meeting join detection | Requires reliable meeting-state inference that the mic-watcher heuristic cannot provide; edge cases outweigh the fix |
| 10 | Append-on-reopen | Depends on reliable title matching, which is currently broken — building on a broken foundation |
| 11 | Per-meeting vocabulary | Pre-recording UI flow adds friction; Whisper's built-in vocabulary is adequate for most meetings |
| 12 | Context snapshot (clipboard capture) | Clipboard is a privacy hazard — frequently contains passwords/tokens; ships before user understands what's being captured |
| 13 | Spotlight search enhancement | Spotlight already indexes Markdown natively on macOS; non-problem |
| 14 | FSEvents rename detection | Low-priority edge case with no stated user pain |
| 15 | Zero-speech detection | Made redundant by WhisperKit's built-in silero-VAD (already in the active plan) |

---

## Session Log
- 2026-04-13: Initial ideation — 31 raw candidates generated across 4 frames (pain/friction, inversion, leverage/edge-cases, output/ecosystem), deduplicated to ~20 unique ideas, 7 survived adversarial filtering
