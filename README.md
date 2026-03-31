# tape

A lightweight macOS menu bar app that records meetings and saves them as Markdown files.

## What it does

- Records audio from your microphone with one click
- Transcribes locally using [Whisper](https://github.com/ggerganov/whisper.cpp) — nothing leaves your machine
- Saves each recording as a `.md` file with YAML frontmatter: title, date, time, duration, speaker
- Auto-detects meeting apps (Zoom, Teams, Slack, etc.) and starts a grace window when they close
- Lets you rename recordings inline and view transcripts in a detail panel

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+

## Building

```
open Tape.xcodeproj
```

Select the **Tape** scheme and run. The app appears in the menu bar as a cassette icon.

> **Note:** Automatic mic-detection (the notification prompt when a meeting starts) requires a signed or notarized build. Manual recording via the Record button works in all builds.

## How recordings work

Each recording is saved to `~/Documents/tape/` by default. You can change this in Settings.

Files are named `YYYY-MM-DD-HH-mm-<title>.md` and contain:

```markdown
---
title: weekly sync
date: 2026-03-31
time: 14:00
duration: 47min
source: Zoom
speakers:
  - Kyle
  - Speaker 2
partial: false
---

## Context



## Transcript

[00:00] Kyle: ...
```

The **Context** section is left blank for you to fill in after the meeting.

## Settings

| Setting | Default | Description |
|---|---|---|
| Output folder | `~/Documents/tape/` | Where `.md` files are saved |
| Your name | — | Used for speaker labeling in the transcript |
| Whisper model | `base` | Transcription model. Larger = more accurate, slower |
| Minimum recording | 5s | Recordings shorter than this are discarded |
| Grace window | 30s | Seconds to wait after meeting ends before finalizing |
| Custom vocabulary | — | Words/phrases to bias transcription toward |

## Whisper models

Models are downloaded on first use to `~/Library/Application Support/tape/models/`.

| Model | Size | Notes |
|---|---|---|
| tiny | ~75 MB | Fast, less accurate |
| base | ~142 MB | Good balance (default) |
| small | ~466 MB | Better accuracy |
| medium | ~1.5 GB | High accuracy |
| large-v3 | ~3.1 GB | Best accuracy, slow |

## License

MIT
