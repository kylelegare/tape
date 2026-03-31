---
date: 2026-03-31
topic: auto-record-detection
---

# Auto-Record Detection

## Problem Frame

tape currently starts recording based on a mic-activity allow list (known meeting apps) and stops based on a polling loop checking if those apps are still running. This causes two failure modes: false positives (brief mic grabs from dictation, AI assistants, IDEs) and stuck recordings (browser-based calls like Google Meet or Teams in Chrome never stop cleanly because Chrome is always running).

Char and Granola both solved this with a two-layer approach: calendar as the primary signal (reliable, clean start/stop boundaries) and mic as a fallback for unscheduled calls. The allow list strategy is fragile — any new meeting tool is silently missed.

## Requirements

- R1. **Deny list instead of allow list** — When mic activity triggers recording, filter out known non-meeting apps (dictation, screen recorders, IDEs, AI voice assistants, music apps) and start recording for everything else. This catches novel meeting apps automatically rather than requiring explicit whitelisting.

- R2. **15-second sustain threshold** — Do not start a recording on the first mic-active signal. Require the mic to stay in use by a non-blocked app for 15 continuous seconds before committing to a recording. Eliminates false triggers from brief dictation, keyboard dictation, or other transient mic use.

- R3. **Calendar end time as stop signal for browser calls** — When a recording was triggered by a calendar event, use the event's end time (plus the grace window) to stop recording. This solves the stuck-recording problem for Google Meet, Teams-in-browser, and any other browser-based call.

- R4. **Manual stop as fallback for unscheduled browser calls** — When recording started from mic activity (not calendar) and no end time is known, rely on the user pressing Stop in the popover. Document this in the UI so users know what to expect.

- R5. **Calendar proximity bridge** — When mic-triggered recording starts within 15 minutes of a calendar event's end time, inherit that event's end time as the stop signal (Granola's pattern). Bridges the gap when Zoom/Teams joins a scheduled call slightly after the calendar event starts.

## Success Criteria

- No false recordings from keyboard dictation, Whisper/AI voice tools, Logitech, or screen recorders
- Zoom/Teams/FaceTime calls stop cleanly without manual intervention
- Google Meet and Teams-in-browser stop cleanly when the meeting was on the calendar
- A brief unexpected mic grab (< 15s) never produces a recording file

## Scope Boundaries

- No cloud calendar integration — ICS feed only, as before
- No speaker diarization or multi-speaker detection
- No attempt to detect browser-based call end without calendar data
- Deny list is a static code list initially; no UI for users to modify it

## Key Decisions

- **Deny list over allow list**: More durable — new apps work automatically, edge cases are opt-out not opt-in
- **15s threshold over immediate start**: Matches Char's production-proven threshold; small enough not to miss real meetings, large enough to kill dictation false positives
- **Calendar end time as stop signal**: Calendar events have known boundaries. Using them for stop detection is reliable. Browsers don't — so they get manual stop for non-calendar calls.
- **Keep existing calendar-first trigger unchanged**: It already works well. These changes improve the mic-fallback path and add stop signal logic.

## Dependencies / Assumptions

- CalendarService already parses event end times from the ICS feed (need to verify and expose if not)
- CoreAudio `kAudioHardwarePropertyProcessObjectList` + bundle ID lookup already available for deny list filtering

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Needs research] What is the complete deny list? Need to enumerate known false-positive apps (Whisper.app, Superpowered, Logitech options, Xcode simulator audio, OBS, etc.)
- [Affects R3][Technical] Does CalendarService currently expose event end times on `UpcomingMeeting`? If not, add `endDate` field.
- [Affects R5][Technical] At what point in the recording lifecycle should the proximity bridge check run — at recording start, or continuously during recording?

## Next Steps

→ `/ce:plan` for structured implementation planning
