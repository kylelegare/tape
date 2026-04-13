---
title: "feat: Migrate to WhisperKit with dual-stream diarization"
type: feat
status: active
date: 2026-04-13
---

# feat: Migrate to WhisperKit with dual-stream diarization

## Overview

Replace SwiftWhisper with WhisperKit (Apple Silicon native, Core ML, built-in VAD), and use the dual audio streams AudioRecorder already captures to produce free speaker diarization — mic track transcribed as the user, system track transcribed as "Others" — without any ML diarization model.

## Problem Frame

Two connected problems:

1. **SwiftWhisper is showing its age.** It wraps whisper.cpp via a C bridge, runs on CPU, and requires manual 16kHz audio conversion. WhisperKit runs the same Whisper models via Core ML on the Neural Engine — faster, smaller models, and has built-in silero-VAD that makes our SoundAnalysis post-filter redundant.

2. **Speaker labeling is fake.** Everything in the transcript is labeled as the user's name because both speakers are mixed into one track before transcription. AudioRecorder already records mic and system audio as separate CAF files before mixing — if we keep those files alive through the transcription step, we get genuine "Kyle" vs "Others" labeling for free, with no diarization model needed.

## Requirements Trace

- R1. Replace SwiftWhisper dependency with WhisperKit Swift Package
- R2. WhisperKit's built-in VAD replaces our SoundAnalysis post-filter — delete the VAD code
- R3. Model management delegates to WhisperKit (HuggingFace download, Core ML caching)
- R4. User-facing model names (tiny, base, small, medium, large-v3) map correctly to WhisperKit identifiers
- R5. Vocabulary injection (initial prompt biasing) preserved via WhisperKit's DecodingOptions
- R6. Mic and system audio tracks transcribed separately and merged by timestamp
- R7. Mic segments labeled with the user's configured name; system segments labeled "Others"
- R8. Final mixed m4a still saved to the output folder (archiving behavior unchanged)
- R9. Separate track CAF files cleaned up after transcription completes

## Scope Boundaries

- No speaker diarization ML model (SpeakerKit, Pyannote) — dual-stream separation is sufficient
- No ScreenCaptureKit — CoreAudio process tap already captures system audio without it
- No LLM cleanup pass — transcript fidelity is intentional for a meeting recorder
- Settings UI model picker label changes are minimal — user-facing names stay the same
- Existing `~/Documents/tape/` output format and frontmatter unchanged

## Context & Research

### Relevant Code and Patterns

- `Tape/Sources/Services/TranscriptionService.swift` — full rewrite; SwiftWhisper usage, manual audio conversion, SoundAnalysis VAD all removed
- `Tape/Sources/Services/AudioRecorder.swift` — `stopRecording()` signature changes to return separate track URLs; mixing logic unchanged
- `Tape/Sources/Services/ModelManager.swift` — replaced by thin WhisperKit model name mapper; download/cache managed by WhisperKit internally
- `Tape/Sources/Services/RecordingManager.swift` — updated to use new `stopRecording()` return value and dual-track transcription
- `Tape/Sources/Views/SettingsView.swift` — model picker options stay the same user-facing names; no visible change expected
- `Tape.xcodeproj/project.pbxproj` — remove SwiftWhisper package + SoundAnalysis framework; add WhisperKit package
- `Tape/Resources/Tape.entitlements` — no changes needed; CoreAudio process tap works without screen-capture entitlement

### Key Existing Patterns

- `AudioRecorder` already writes `tape-mic-{ts}.caf` and `tape-sys-{ts}.caf` separately, then mixes. The separate files exist on disk during the recording session — we just need them to survive until transcription is done.
- `TranscriptionService.transcribe()` is called once per recording in `RecordingManager.finalizeRecording()`. Calling it twice (mic + system) and merging is a contained change in that one method.
- WhisperKit's `transcribe(audioPath:decodeOptions:)` accepts a file path string and handles format conversion internally — the entire `loadAudioSamples` and `AVAudioConverter` pipeline in TranscriptionService is deleted.
- Vocabulary biasing maps directly: current `whisper.params.initial_prompt` → `DecodingOptions.initialPrompt` in WhisperKit.

### WhisperKit Model Name Mapping

| User-facing | WhisperKit identifier |
|---|---|
| tiny | openai_whisper-tiny |
| base | openai_whisper-base |
| small | openai_whisper-small |
| medium | openai_whisper-medium |
| large-v3 | openai_whisper-large-v3 |

WhisperKit caches Core ML models at `~/Library/Application Support/argmaxinc/WhisperKit/`. Previously cached `.bin` files in `~/Library/Application Support/Tape/models/` are unused after migration — they can be left in place (harmless) or cleaned up lazily.

## Key Technical Decisions

- **WhisperKit instance per transcription vs cached:** Create a new `WhisperKit` instance per transcription call. Tape transcribes infrequently (once per meeting), so the initialization overhead is acceptable and avoids stale model state if the user changes the model in Settings mid-session.

- **stopRecording() return type:** Change from `async -> Void` to `async -> RecordingTracks` (a struct with `mixedURL`, `micURL?`, `systemURL?`). `RecordingManager` is responsible for cleanup after transcription. This is the minimal surface change — AudioRecorder's internal logic is unchanged.

- **System track absent:** If system audio capture failed at start (e.g. no audio processes), `systemURL` is nil. `RecordingManager` falls back to mic-only transcription and labels everything as the user's name — same behavior as today.

- **Segment merge strategy:** Interleave mic and system segments sorted by `startTime`. No gap-filling or silence alignment needed — WhisperKit timestamps are relative to the input file, and both files start at the same wall-clock time (recording start).

- **SoundAnalysis framework:** Removed from both code and `project.pbxproj` — WhisperKit's silero-VAD runs pre-transcription and makes our post-filter redundant.

- **ModelManager.swift:** Simplify to a static name mapper only. WhisperKit handles download, progress reporting, and caching itself. The `@Published` download progress properties can be removed or wired to WhisperKit's progress callback if desired — defer to implementation.

## Open Questions

### Resolved During Planning

- **Does AudioRecorder need ScreenCaptureKit?** No — it already uses CoreAudio process tap (`CATapDescription`, `AudioHardwareCreateProcessTap`) which works without the screen-capture entitlement. The system audio stream is already there.
- **Do we need to convert CAF files to m4a before passing to WhisperKit?** No — WhisperKit's transcribe accepts any AVFoundation-readable format including CAF.
- **Does WhisperKit support macOS 15 deployment target?** Yes — supports macOS 13+.

### Deferred to Implementation

- Whether to wire WhisperKit's download progress callbacks into any UI indicator — ModelManager currently shows download progress in Settings. Defer to implementation to decide if that's worth preserving.
- Exact behavior when both mic and system tracks produce overlapping timestamps (e.g., the user is also speaking while system audio plays) — stable sort by startTime is the safe default; revisit if output looks wrong in practice.
- Whether to delete old `.bin` model files from `~/Library/Application Support/Tape/models/` on first launch — low priority, defer.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification.*

```
Recording session:
  AudioRecorder.startRecording()
    → tape-mic-{ts}.caf    (mic)
    → tape-sys-{ts}.caf    (system, optional)

AudioRecorder.stopRecording() → RecordingTracks
    → mixes to tape-{ts}.m4a  (saved file, unchanged)
    → returns micURL + systemURL (NOT deleted yet)

RecordingManager.finalizeRecording()
    → WhisperKit.transcribe(micURL)    → mic segments  [Kyle: ...]
    → WhisperKit.transcribe(systemURL) → sys segments  [Others: ...]
    → merge + sort by startTime
    → formatTranscript(mergedSegments)
    → cleanup micURL + systemURL
    → write .md to output folder
```

## Implementation Units

- [ ] **Unit 1: Swap package dependency**

  **Goal:** Remove SwiftWhisper, add WhisperKit. Project compiles with the new dependency.

  **Requirements:** R1

  **Dependencies:** None

  **Files:**
  - Modify: `Tape.xcodeproj/project.pbxproj` — remove SwiftWhisper XCRemoteSwiftPackageReference + product dependency + build file; add WhisperKit package reference and product dependency
  - Modify: `Tape/Resources/Tape.entitlements` — no change expected, confirm

  **Approach:**
  - WhisperKit Swift Package URL: `https://github.com/argmaxinc/WhisperKit.git`
  - Use a recent tagged release (0.17+ for open-source diarization support; 0.18 is latest as of April 2026)
  - SoundAnalysis.framework reference in project.pbxproj is also removed here since VAD code is going away

  **Verification:**
  - Project builds with `import WhisperKit` resolving correctly
  - `import SwiftWhisper` and `import SoundAnalysis` produce errors (confirming removal)

---

- [ ] **Unit 2: Rewrite TranscriptionService**

  **Goal:** Transcription uses WhisperKit. Manual audio conversion, SoundAnalysis VAD, and all whisper.cpp-specific code are deleted.

  **Requirements:** R2, R3, R4, R5

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `Tape/Sources/Services/TranscriptionService.swift` — near-complete rewrite
  - Delete interior: `SpeechDetectionDelegate`, `filterHallucinations`, `detectSpeechRanges`, `loadAudioSamples`, `TranscriptionError` (or slim down)

  **Approach:**
  - `transcribe(audioURL:modelName:vocabulary:speakerName:)` — signature changes: `modelPath: URL` → `modelName: String` (WhisperKit resolves the path)
  - Initialize `WhisperKit(model: whisperKitModelName(for: modelName))` at call time
  - Pass `DecodingOptions(initialPrompt: vocabulary.joined(separator: ", "))` when vocabulary is non-empty
  - WhisperKit returns `[TranscriptionResult]?`; each result has `.segments` with `.text`, `.start`, `.end` (Float in seconds — convert to ms for `TranscriptSegment` or change `TranscriptSegment` to use seconds)
  - `formatTranscript` updated to accept a speaker label per segment (prep for Unit 5)

  **Patterns to follow:**
  - Keep `TranscriptResult` and `TranscriptSegment` structs — only internals change
  - Keep `applyVocabularyCorrections` unchanged
  - Keep `formatTranscript` shape, extend it

  **Test scenarios:**
  - Transcription of a short m4a produces non-empty segments
  - Vocabulary word appears correctly in output when provided
  - Empty vocabulary does not pass an empty initial prompt to WhisperKit
  - Unknown model name surfaces a clear error

  **Verification:**
  - `filterHallucinations` call sites in RecordingManager produce a compile error (confirming deletion)
  - A test recording transcribes successfully end-to-end

---

- [ ] **Unit 3: Simplify ModelManager**

  **Goal:** ModelManager becomes a static name mapper. WhisperKit owns downloading and caching.

  **Requirements:** R3, R4

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `Tape/Sources/Services/ModelManager.swift` — remove download logic, URLSession delegate, progress tracking; keep model name → WhisperKit identifier mapping
  - Modify: `Tape/Sources/Services/RecordingManager.swift` — remove `ensureModel()` call and `statusMessage = "downloading…"` branch; WhisperKit handles this transparently

  **Approach:**
  - `ModelManager` reduces to a static helper: `static func whisperKitID(for name: String) -> String`
  - The `@Published downloadProgress` and `isDownloading` properties can be removed; if a progress indicator is still wanted, defer to a follow-up
  - `SettingsView`'s model picker uses the same string keys ("tiny", "base", etc.) — no UI change needed
  - `ModelManager.shared` singleton can be removed; make it a pure static utility or a simple enum

  **Verification:**
  - RecordingManager no longer calls `ModelManager.shared.ensureModel()`
  - Settings model picker still shows correct options and saves the selection

---

- [ ] **Unit 4: Separate track output from AudioRecorder**

  **Goal:** `stopRecording()` returns both the mixed URL and the separate track URLs. AudioRecorder no longer cleans up the CAF files — that responsibility moves to RecordingManager.

  **Requirements:** R6, R8, R9

  **Dependencies:** None (parallel with Units 2–3)

  **Files:**
  - Modify: `Tape/Sources/Services/AudioRecorder.swift` — change `stopRecording() async -> Void` to `stopRecording() async -> RecordingTracks`; add `RecordingTracks` struct; remove CAF cleanup from `stopRecording()`
  - Modify: `Tape/Sources/Services/RecordingManager.swift` — update call site to capture `RecordingTracks`; add cleanup of `micURL` and `systemURL` after transcription

  **Approach:**
  ```
  struct RecordingTracks {
      let mixedURL: URL       // final .m4a, for archiving
      let micURL: URL         // mic-only .caf, for transcription
      let systemURL: URL?     // system-only .caf, nil if capture failed
  }
  ```
  - Mixing logic in `stopRecording()` is unchanged — it still produces the m4a
  - CAF files are NOT deleted in `stopRecording()` — RecordingManager deletes them after transcription (or on error)
  - `startRecording()` return value: keep returning the `mixedURL` path as before (RecordingManager stores it as `audioFileURL` for archiving)

  **Verification:**
  - After `stopRecording()`, all three files exist on disk: mixed m4a, mic CAF, system CAF
  - After transcription, CAF files are deleted
  - If system capture failed at start, `systemURL` is nil and RecordingManager handles it without crashing

---

- [ ] **Unit 5: Dual-stream transcription and merged output**

  **Goal:** Mic and system tracks are transcribed separately. Transcript interleaves "Kyle:" and "Others:" segments sorted by timestamp.

  **Requirements:** R6, R7

  **Dependencies:** Units 2, 4

  **Files:**
  - Modify: `Tape/Sources/Services/RecordingManager.swift` — `finalizeRecording()` calls `transcribe()` twice, merges results
  - Modify: `Tape/Sources/Services/TranscriptionService.swift` — `formatTranscript` accepts speaker label per segment or a labeled segment type

  **Approach:**
  - Add a `speaker: String` field to `TranscriptSegment` (or create `LabeledSegment`)
  - `RecordingManager` transcribes mic → tags each segment `.speaker = userName`
  - `RecordingManager` transcribes systemURL (if present) → tags each segment `.speaker = "Others"`
  - Merge both arrays, sort by `startMs`
  - Pass merged array to `formatTranscript`
  - If `systemURL` is nil, all segments get the user's name (current behavior)
  - Output format: `**Kyle:** segment text` / `**Others:** segment text`

  **Patterns to follow:**
  - `formatTranscript` already maps over segments — just reads `.speaker` instead of `result.speakerName`

  **Test scenarios:**
  - Mic-only recording: all segments labeled with user's name
  - Dual-stream recording: segments from both tracks interleaved by timestamp
  - System track absent: graceful fallback, no crash
  - Segments with identical start times: stable sort preserves mic-first order

  **Verification:**
  - A dual-stream recording produces a transcript with both "Kyle:" and "Others:" labels
  - Timestamps in the output are in ascending order
  - CAF temp files are removed after transcription completes

## System-Wide Impact

- **RecordingManager** is the central coordinator and touches all units — Units 2, 3, 4, 5 all require RecordingManager changes; sequence them to avoid merge conflicts by doing Units 2+3 in one pass, then Unit 4, then Unit 5
- **`filterHallucinations` removal:** RecordingManager currently calls this explicitly — removing it is a compile-time error to catch, not a silent omission
- **Old model files:** `.bin` files in `~/Library/Application Support/Tape/models/` become orphans. No active cleanup — they're inert.
- **SettingsView:** No changes needed to the model picker — user-facing names ("tiny" etc.) are preserved. Verify the stored UserDefaults key "whisperModel" still resolves correctly through the new name mapper.

## Risks & Dependencies

- **WhisperKit first-run model download:** WhisperKit downloads Core ML models on first use, same as before. The "downloading model…" status message in the UI is currently driven by `ModelManager` — after Unit 3, this disappears unless wired to WhisperKit's progress callbacks. Acceptable for now; the transcription will still complete, just silently.
- **CAF format support in WhisperKit:** WhisperKit uses AVFoundation internally and should read CAF files without issue, but this is worth confirming early in implementation.
- **Dual transcription time:** Two WhisperKit calls per recording means roughly 2x transcription time. For typical meeting lengths (30–60 min) on Apple Silicon with tiny/base models, this should still be fast. Monitor in practice.
- **System audio absent in most recordings:** Many recordings will have no system audio (e.g. in-person meetings, manual Record button usage). The `systemURL == nil` fallback path must be rock solid.

## Sources & References

- WhisperKit repo: https://github.com/argmaxinc/WhisperKit
- WhisperKit latest release: v0.18.0 (April 2026)
- Ghost Pepper (reference implementation using WhisperKit + dual-stream): https://github.com/matthartman/ghost-pepper
- Current `AudioRecorder.swift` — dual-stream capture already implemented, just needs output API change
- Current `TranscriptionService.swift` — full file to be rewritten in Unit 2
