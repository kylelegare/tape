---
date: 2026-04-13
topic: eventkit-calendar-naming
---

# EventKit Calendar-Based Meeting Naming

## Problem Frame

Tape's auto-detected meeting titles are often useless — the window title fallback produces "Zoom Meeting" and the final fallback is just the app name ("Zoom"). The user ends up with files named `2026-04-13-11-30-zoom.md` when their calendar says "Q2 Planning". EventKit provides on-device, no-network access to the user's calendar, making it the most reliable source of intentional meeting titles.

## Requirements

- R1. At recording start, Tape queries EventKit for all calendar events across all of the user's calendars.
- R2. An event is a candidate match if it is currently in progress (started before recording start and has not ended) or starts within the next 5 minutes.
- R3. From all candidate matches, Tape selects the one with the most recent start time (the meeting the user most likely just joined). If two events have the same start time, the first one returned by EventKit is used.
- R4. The selected event's title is used as the meeting title. The existing chain becomes: **calendar event → window title → app name.**
- R5. If no candidate events match, Tape falls through to the existing window-title detection with no user-visible change.
- R6. If EventKit access is denied, restricted, or throws an error, Tape silently falls through to the existing chain. No error message is shown.
- R7. Calendar permission is requested at first use via the standard OS dialog (no extra Tape UI). If the user denies it, R6 applies permanently until they grant access in System Settings.
- R8. The `source` field in the Markdown frontmatter continues to reflect the recording app (e.g., "Zoom"), not "Calendar". The title comes from the calendar but the meeting happened in that app.

## Scope Boundaries

- No calendar UI in Tape's Settings or popover — this is fully automatic.
- No attendee extraction or display from EventKit (frontmatter `speakers` field is not populated from calendar).
- No write-back to the calendar (no event updates, notes, or attachments).
- No per-calendar filtering — all calendars are queried, including personal, work, and shared.
- No disambiguation UI when multiple events match — the most-recently-started event wins silently.

## Success Criteria

- A recording started during "Q2 Planning" produces a file titled "Q2 Planning", not "Zoom".
- A recording started with no matching calendar events produces the same title as today (window title or app name).
- Denying calendar permission does not crash Tape or show an error.
- Back-to-back meetings: starting a recording 2 minutes into the second meeting produces the second meeting's title, not the first.

## Key Decisions

- **Calendar before window title**: Calendar events represent the user's intent for what the meeting is. Window titles are often generic ("Zoom Meeting") or noisy. Calendar wins.
- **Silent permission request**: Consistent with how Tape handles mic permission — macOS handles the dialog, Tape just makes the request. No explanation UI needed for v1.
- **Graceful degradation on denial**: Tape should never surface calendar errors to the user. The existing fallback chain is good enough.
- **No attendee data in v1**: Keeping scope tight. Attendees are a useful addition later but add complexity (privacy, formatting, deduplication against the user's own name).

## Dependencies / Assumptions

- `NSCalendarsUsageDescription` key must be added to Info.plist (required by EventKit).
- EventKit calendar access is supported on macOS 10.8+; well within Tape's deployment target.
- `MeetingIdentity.resolve()` is `@MainActor` and async-friendly — EventKit queries can be awaited there.

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Technical] EventKit's async API changed in macOS 14 (structured concurrency support). Confirm which API surface to use given the deployment target.
- [Affects R3][Technical] Whether `EKEventStore.requestAccess` should be cached in a shared instance or called fresh each time — EventKit stores are typically singletons.

## Next Steps

→ `/ce:plan` for structured implementation planning
