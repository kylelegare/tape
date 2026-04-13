---
title: "feat: EventKit calendar-based meeting naming"
type: feat
status: active
date: 2026-04-13
origin: docs/brainstorms/2026-04-13-eventkit-calendar-naming-requirements.md
---

# feat: EventKit calendar-based meeting naming

## Overview

Insert EventKit calendar lookup as the first layer in `MeetingIdentity.resolve()`, so recordings made during a calendar event are named after that event ("Q2 Planning") rather than falling back to the Zoom window title or "Zoom". Fully local, no network, zero visible UI change.

## Problem Frame

Auto-detected meeting titles are often generic — Zoom's window title is frequently "Zoom Meeting" and the final fallback is just the app name. The user's calendar already contains the intentional title for the meeting. EventKit reads it on-device with no dependencies.

(see origin: docs/brainstorms/2026-04-13-eventkit-calendar-naming-requirements.md)

## Requirements Trace

- R1. At recording start, query EventKit across all calendars for in-progress or imminently starting events
- R2. Match = currently in progress (started ≤ now, not yet ended) OR starting within the next 5 min
- R3. From matches, select the event with the most recent start time (most likely the meeting just joined)
- R4. Priority chain: calendar event → window title → app name
- R5. Any failure (denied, error, no match) silently falls through to the next layer
- R6. Calendar permission is requested at first use via the OS dialog; denial makes R5 permanent
- R7. `source` frontmatter field remains the recording app, not "Calendar"
- R8. `resolve()` must remain `@MainActor`-safe after the change

## Scope Boundaries

- No calendar UI in Settings or popover
- No attendee extraction
- No write-back to the calendar
- All-day events excluded (not meetings)
- No disambiguation prompt when multiple events match — silent heuristic only

## Context & Research

### Relevant Code and Patterns

- `Tape/Sources/Services/MeetingIdentity.swift` — the only file changed for the calendar logic. `resolve()` is a `@MainActor` static method returning `MeetingIdentity` synchronously today. The layered early-return pattern (`if let … { return }`) is the existing convention.
- `Tape/Sources/Services/RecordingManager.swift` — two call sites: `startOneOffRecording()` and `startRecordingFromPrompt()`. Both currently call `resolve()` synchronously then spawn a `Task { await startRecording(...) }`. Making `resolve()` `async` requires wrapping both call sites in `Task { let identity = await MeetingIdentity.resolve(); await startRecording(identity: identity) }` — the actor context is already correct since `RecordingManager` is `@MainActor`.
- `Tape/Resources/Info.plist` — currently has `NSMicrophoneUsageDescription` and `NSAudioCaptureUsageDescription`. `NSCalendarsFullAccessUsageDescription` must be added.
- `Tape/Resources/Tape.entitlements` — app sandbox is **off**. No entitlement change needed; TCC still enforces calendar permission via the usage description key.

### Key Research Findings

- **Deployment target is macOS 15.0** — `EKEventStore.requestFullAccessToEvents()` as `async throws` is available directly. No `#available` guard or legacy `requestAccess(to:completion:)` needed.
- **`events(matching:)` is synchronous** — must be wrapped in `await Task.detached { }.value` or similar to avoid blocking the main thread, even though the time window is short.
- **EKEventStore must be a long-lived singleton** — Apple docs warn that releasing the store before its returned objects causes errors. A `private static let store = EKEventStore()` on `MeetingIdentity` is the least-friction approach for a stateless struct.
- **Authorization status to check**: `.fullAccess` (the macOS 14+ status enum value). Anything else falls through.
- **Predicate window**: `now - 4h` to `now + 5min` to safely capture long meetings in progress. The returned events are then filtered in Swift for the exact match conditions (R2).
- **No entitlement needed** — confirmed Tape.entitlements has `com.apple.security.app-sandbox = false`.

## Key Technical Decisions

- **`resolve()` becomes `async`**: The async EventKit request must be awaited. `@MainActor` is preserved — `Task { }` in RecordingManager inherits the main actor. The existing synchronous window-title lookup (Accessibility API) is fast enough to run inline.
- **Static singleton EKEventStore**: `private static let store = EKEventStore()` on `MeetingIdentity`. Initialized lazily on first use, held for app lifetime. No separate service class needed for something this narrow.
- **`events(matching:)` dispatched via `Task.detached`**: The call is synchronous and could block the main thread. Wrap it in a `Task.detached { ... }.value` await to run it on a background thread.
- **Sort by startDate descending, take first**: "Most recently started" = the meeting the user just joined in a back-to-back scenario. This is a silent heuristic; no disambiguation UI.
- **All-day events filtered out**: `event.isAllDay == true` events are not meetings and would produce wrong titles ("Kyle's Birthday", "PTO").
- **`source` field unchanged**: Continues to reflect the recording app (e.g. "Zoom"). Calendar is only the title source.

## Open Questions

### Resolved During Planning

- **Which EventKit authorization API?** `EKEventStore.requestFullAccessToEvents() async throws` — available on macOS 14+, deployment target is macOS 15. No legacy API or availability guard needed.
- **Singleton or per-query EKEventStore?** Singleton (`private static let`). Apple docs require the store to outlive its returned objects.
- **Entitlement required?** No — Tape is not sandboxed. Usage description key in Info.plist is sufficient.
- **Info.plist key?** `NSCalendarsFullAccessUsageDescription` (macOS 14+ key for read access).

### Deferred to Implementation

- Whether to observe `EKEventStoreChanged` notifications to invalidate any future caching — low priority since Tape queries on-demand at recording start, not on a timer.
- Whether a 4-hour lookback window is the right predicate width in practice — tune if users report mismatches on very long meetings.

## Implementation Units

- [ ] **Unit 1: EventKit calendar layer in MeetingIdentity**

  **Goal:** Add calendar event lookup as the first layer in `MeetingIdentity.resolve()`. The method becomes `async`. Info.plist gets the calendar usage description key.

  **Requirements:** R1, R2, R3, R4, R5, R6, R7, R8

  **Dependencies:** None

  **Files:**
  - Modify: `Tape/Sources/Services/MeetingIdentity.swift`
  - Modify: `Tape/Resources/Info.plist`

  **Approach:**
  - Add `import EventKit` at the top of MeetingIdentity.swift
  - Add `private static let store = EKEventStore()` as a static stored property on the struct
  - Change `static func resolve() -> MeetingIdentity` to `static func resolve() async -> MeetingIdentity`
  - Add a new private static async helper `calendarMatch(now:) async -> String?` that:
    1. Checks `EKEventStore.authorizationStatus(for: .event)` — if not `.fullAccess`, request it via `try await store.requestFullAccessToEvents()`; on error or denial, return nil
    2. Builds a predicate: `now - 4 hours` to `now + 5 minutes`, all calendars (nil)
    3. Dispatches `store.events(matching: predicate)` on a background thread via `Task.detached { }.value`
    4. Filters results: exclude `isAllDay`, keep events where `startDate <= now && endDate > now` OR `startDate > now && startDate <= now + 5 min`
    5. Sorts by `startDate` descending, returns `first?.title`
  - In `resolve()`, call `calendarMatch` first:
    ```
    if let title = await calendarMatch(now: Date()), !title.isEmpty {
        return MeetingIdentity(title: title, source: appName)
    }
    // existing window-title layer follows unchanged
    ```
  - In Info.plist, add key `NSCalendarsFullAccessUsageDescription` with a user-facing string explaining why Tape accesses the calendar

  **Patterns to follow:**
  - Existing early-return `if let … { return }` layering pattern in `resolve()`
  - `cleanWindowTitle` as a model for a private static helper on the struct

  **Test scenarios:**
  - One in-progress event: `resolve()` returns that event's title
  - One event starting in 3 minutes: `resolve()` returns that event's title
  - All-day event overlapping recording time: filtered out, falls through to window title
  - No matching events: falls through to window title layer, no visible change
  - Calendar permission denied: falls through silently, no error or crash
  - EventKit throws an error: caught, returns nil, falls through silently
  - Two in-progress events (back-to-back): returns the one with the later start time

  **Verification:**
  - Build succeeds with `import EventKit` and the new `async` signature
  - A test recording made during a calendar event resolves to the event title
  - A test recording made outside any calendar event resolves exactly as before (window title or app name)
  - Denying calendar access in System Settings produces no UI error and falls back correctly

---

- [ ] **Unit 2: Update RecordingManager call sites**

  **Goal:** Update the two `MeetingIdentity.resolve()` call sites in RecordingManager to `await` the now-async method.

  **Requirements:** R8 (resolve() remains @MainActor-safe)

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `Tape/Sources/Services/RecordingManager.swift`

  **Approach:**
  - `startOneOffRecording()` and `startRecordingFromPrompt()` currently call `resolve()` synchronously then spawn a Task. Restructure each to:
    ```
    Task {
        let identity = await MeetingIdentity.resolve()
        await startRecording(identity: identity)
    }
    ```
  - The `Task { }` body inherits `@MainActor` because both methods are on the `@MainActor` RecordingManager — no actor isolation change
  - No other RecordingManager logic changes

  **Patterns to follow:**
  - Existing `Task { await startRecording(...) }` pattern in the same methods — this is a minimal restructure of code that already exists

  **Test scenarios:**
  - Manual Record button triggers recording and correctly uses the calendar title if a match exists
  - Notification-prompted recording (startRecordingFromPrompt) behaves identically

  **Verification:**
  - Project compiles with no actor isolation warnings
  - Both entry points produce a recording with the expected title

## System-Wide Impact

- **`MeetingIdentity.resolve()` becomes async**: This is the only breaking change. Both call sites are in RecordingManager and are updated in Unit 2. No other callers exist in the codebase.
- **No state machine changes**: RecordingManager's state transitions are unchanged — the EventKit query happens before `startRecording()` is called, so it does not affect the `.recording` / `.transcribing` / `.idle` lifecycle.
- **First-run permission dialog**: On first recording after install, macOS will show a calendar permission dialog. This is the expected behavior and requires no special handling in Tape.

## Risks & Dependencies

- **`events(matching:)` latency**: The synchronous EventKit call is fast for a narrow time window but theoretically unbounded. Running it via `Task.detached` mitigates main-thread blocking; in practice, calendar databases on modern Macs are small and the call should complete in under 10ms.
- **Calendar permission as a new onboarding moment**: Users will see a new OS permission dialog on their first recording after this change is shipped. The usage description string should be clear — "Tape uses your calendar to name recordings after your current meeting." A vague string here will cause confusion or denial.
- **EKEventStore initialization cost**: The first time the static `store` property is accessed, EventKit initializes and may briefly access the calendar database. This should be negligible but is worth noting.

## Sources & References

- **Origin document:** [docs/brainstorms/2026-04-13-eventkit-calendar-naming-requirements.md](docs/brainstorms/2026-04-13-eventkit-calendar-naming-requirements.md)
- Apple: [TN3153: Adopting API changes for EventKit in iOS 17, macOS 14, and watchOS 10](https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos)
- Apple: [Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- Related code: `Tape/Sources/Services/MeetingIdentity.swift`, `Tape/Sources/Services/RecordingManager.swift`
