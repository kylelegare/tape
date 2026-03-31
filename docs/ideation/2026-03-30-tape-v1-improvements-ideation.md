---
date: 2026-03-30
topic: tape-v1-improvements
focus: lightweight transcription app improvements
---

# Ideation: Tape V1 Improvements

## Codebase Context

- **Project shape:** Greenfield macOS menu bar app (Swift + SwiftUI). No code yet -- only `tape-spec.md` and `tape-kickoff-prompt.md` exist. Build tooling: XcodeBuildMCP + Claude Code.
- **Core loop:** Any app grabs mic -> Tape records (mic + system audio via ScreenCaptureKit) -> whisper.cpp transcribes locally -> structured `.md` file drops into a folder.
- **Philosophy:** No AI summaries, no cloud, no database, no accounts. `.md` files are the source of truth. Output designed for downstream agent consumption.
- **Key gaps in spec:** No permission request UX, no error states, speaker diarization unspecified (whisper.cpp doesn't do it natively), no search/filtering, no full app window (user wants one).
- **Key risks:** ScreenCaptureKit entitlements + sandbox, mic polling lag on release, whisper.cpp Metal acceleration needed for speed, ICS timezone parsing, macOS deployment target conflict (spec says 15+, kickoff says 13+).
- **Constraint from user:** Must stay lightweight. These are improvements to the spec, not scope expansions.

## Ranked Ideas

### 1. Permission Onboarding as a First-Run Ceremony
**Description:** A dedicated first-launch window that walks through mic, screen recording, and folder access permissions in sequence with live status feedback. The only time Tape should show a full window uninvited.
**Rationale:** Without this, Tape silently fails. ScreenCaptureKit and mic permissions are required for any recording. macOS will not re-prompt if denied. Both critique passes rated this non-optional.
**Downsides:** Adds a full SwiftUI window just for first launch. Minor scope.
**Confidence:** 95%
**Complexity:** Low
**Status:** Unexplored

### 2. Resilient Recording Pipeline (live streaming + decoupled transcription)
**Description:** Stream transcript lines to the `.md` file in real-time during recording (append-only). Decouple transcription from recording into a persistent background queue that resumes on relaunch. Include a disk-space check before starting any recording.
**Rationale:** Combines three reinforcing ideas into one architectural decision. Live streaming means the file is useful even if the app crashes. Decoupling means recording never competes with CPU-heavy whisper work. Disk checks prevent silent corruption. This is the correct output architecture.
**Downsides:** Background queue adds process lifecycle complexity. Resume-on-launch requires serializing queue state.
**Confidence:** 85%
**Complexity:** Medium
**Status:** Unexplored

### 3. Post-Meeting Grace Window
**Description:** When the mic releases, start a 30-second visible countdown in the menu bar before finalizing. During this window, the user can extend recording (for post-call dictation) or cut it short. After the window closes, trigger transcription.
**Rationale:** Turns the mic-polling lag from a bug into a feature. The seconds immediately after a call ends are high-value capture moments -- people dictate action items, reactions, and next steps. Zero infrastructure cost.
**Downsides:** Adds 30 seconds of latency before transcription starts. Should be configurable.
**Confidence:** 80%
**Complexity:** Low
**Status:** Unexplored

### 4. Graceful Meeting Identity (layered, not calendar-dependent)
**Description:** Build meeting title resolution as a fallback chain: (1) Accessibility API reads Zoom/Teams window title, (2) ICS feed matches by time window, (3) frontmost app name + timestamp. Calendar enrichment is additive and retroactive -- never a prerequisite. The app works fully with zero configuration.
**Rationale:** ICS feeds are brittle and require setup. Ad-hoc calls never have calendar events. The window-title approach covers the majority case with one API call. Making calendar optional means zero-config first use.
**Downsides:** Accessibility API access to window titles can be fragile across app versions. Must fail gracefully.
**Confidence:** 80%
**Complexity:** Low-Medium
**Status:** Unexplored

### 5. Calendar Pre-Arming
**Description:** When an ICS event is 60 seconds away, pre-arm recording. The mic poll becomes a fallback for ad-hoc calls only. The meeting title is known before the first word is spoken, and the whisper prompt can be seeded with context.
**Rationale:** Inverts the trigger model. The current reactive approach structurally misses the first 5-10 seconds of every meeting. Calendar events encode intent before the fact. Pre-arming eliminates the cold-start gap.
**Downsides:** Requires a background timer. Adds complexity if the calendar event is cancelled or rescheduled. Only helps for scheduled meetings.
**Confidence:** 75%
**Complexity:** Medium
**Status:** Unexplored

### 6. Adaptive Vocabulary Learning
**Description:** After each meeting, diff user corrections in the Context section against the raw transcript. Automatically promote corrected terms into the whisper initial prompt for future recordings. The vocabulary list learns from edits over time.
**Rationale:** Eliminates manual find/replace maintenance. Each correction compounds -- after 10 meetings, domain jargon accuracy improves without explicit configuration. Deterministic, not generative.
**Downsides:** Risk of prompt bloat degrading general accuracy. Needs a vocabulary size cap. Requires a diffing mechanism.
**Confidence:** 70%
**Complexity:** Medium
**Status:** Unexplored

### 7. Full App Window
**Description:** A proper NSWindow accessible from the menu bar (double-click or menu item). Hosts a timeline of past recordings, search over transcript content, and the detail panel inline. Dock icon appears only when this window is open.
**Rationale:** User wants this. A menu bar popover is appropriate for quick status but inadequate for reviewing past meetings. Once you have 20+ transcripts, the popover becomes a navigation bottleneck.
**Downsides:** Significant UI surface area -- effectively doubles the view layer. Biggest single addition to the spec. Consider as V1.1 or V2.
**Confidence:** 65%
**Complexity:** High
**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | SQLite instead of .md files | Directly contradicts core philosophy |
| 2 | Local semantic search | Mini-infrastructure project, premature for V1 |
| 3 | Transcript confidence heatmap | Three hard problems (token probs, custom renderer, audio seeking) |
| 4 | Persistent speaker identity graph | Research-grade feature, needs model pipeline |
| 5 | Heuristic speaker diarization | Bad diarization harder to read than clean monologue |
| 6 | Topic segmentation | TF-IDF over single transcript too sparse |
| 7 | Action item extraction | Regex NLP on natural language notoriously brittle |
| 8 | Temporal vocabulary index | Intermediate artifact with no consumer |
| 9 | Meeting lineage linking | Requires speaker identity that doesn't exist |
| 10 | Meeting continuity stitching | Audio fingerprinting is non-trivial DSP |
| 11 | Silence & interruption metadata | Requires accurate diarization |
| 12 | Reverse-order transcription | Whisper not designed for this |
| 13 | App-context vocabulary profiles | Premature, no correction data yet |
| 14 | Overlapping meeting tracks | Can't attend two meetings simultaneously |
| 15 | Git repo for meeting history | Folder with timestamps sufficient |
| 16 | Structured meeting template | Generalization of nonexistent problem |
| 17 | Ambient context snapshot | Privacy surface large, use case vague |
| 18 | QuickLook plugin | .md already previews in Finder |
| 19 | Obsidian/Logseq vault detection | Just point output folder at vault |
| 20 | Frontmatter schema contract | Documentation infra, not product feature |
| 21 | Video drop target | Scope creep |
| 22 | Error state audit log | Console.app exists; simple log file suffices |
| 23 | Per-meeting model selection | Pick one model, revisit later |
| 24 | Audio redaction markers | Substantial implementation; simpler to delete file |
| 25 | Language auto-detection | Near-zero value for personal use |
| 26 | Schema version flags | Too minor; add if schema evolves |
| 27 | Participant list from Accessibility API | Fragile across app updates |

## Session Log
- 2026-03-30: Initial ideation -- 48 candidates generated across 6 frames, 37 unique after dedup, 7 survived two-layer adversarial filtering. User confirmed set and emphasized lightweight constraint.
