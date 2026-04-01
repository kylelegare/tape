# tape

```text
  ______________________________
 |  ________________  ________  |
 | |                ||        | |
 | |   local-first  ||  .md   | |
 | |    meeting     || files  | |
 | |    recorder    ||        | |
 | |________________||________| |
 |  ___      _________      ___ |
 | / _ \    / ======= \    / _ \|
 || |_| |  |  tape.app |  | |_| ||
 ||_____|   \_________/   |_____||
 |______________________________|
```

Lightweight macOS menu bar recorder for people who want transcripts as plain Markdown files, not trapped in another web app.

## Why tape

Most meeting tools optimize for sync, sharing, and dashboards.

`tape` optimizes for a different loop:

- click `Record`
- talk
- click `Stop`
- get a local `.md` file an agent can read

No cloud account. No browser tab. No weird export step.

## What it does

- Lives in the macOS menu bar
- Records from your microphone with a simple manual start/stop flow
- Transcribes locally with Whisper
- Saves each recording as a Markdown file with YAML frontmatter
- Lets you rename recordings inline and inspect them in a detail panel
- Keeps the output easy for humans and agents to parse

## Why Markdown

Every recording becomes a file you actually own.

- easy to grep
- easy to sync with git, iCloud, Dropbox, or Obsidian
- easy to hand to coding agents and local tools
- easy to edit after the meeting

Example output:

```markdown
---
title: "Weekly Sync: Core"
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

- Roadmap review
- Q2 planning

## Transcript

[00:00] Kyle: ...
```

## Product shape

`tape` is intentionally narrow:

- manual recording only
- local-first transcription
- one file per recording
- minimal background behavior

That constraint is the point. The app should feel light, predictable, and durable.

## Requirements

- macOS 15+
- Xcode 16+

## Build From Source

```bash
open Tape.xcodeproj
```

Run the `Tape` scheme. The app appears in the menu bar as a cassette icon.

For a clean installed app:

```bash
xcodebuild -project Tape.xcodeproj -scheme Tape -configuration Release build
```

The built app bundle will be in Xcode DerivedData or the custom derived-data path you choose.

## Recording Files

By default, recordings are written to `~/Documents/tape/`.

Filename format:

```text
YYYY-MM-DD-HH-mm-title.md
```

The `Context` section is left blank on purpose so you can add notes, decisions, and follow-ups after the call.

## Settings

| Setting | Default | Description |
|---|---|---|
| Output folder | `~/Documents/tape/` | Where `.md` files are saved |
| Launch at login | Off | Starts the menu bar app when you log in |
| Your name | — | Used to label your speaker name in transcripts |
| Whisper model | `tiny` | Downloads on first use |
| Minimum recording | `5s` | Short recordings are discarded |
| Custom vocabulary | — | Biases transcription toward names and project terms |

## Whisper Models

Models are downloaded on first use to:

```text
~/Library/Application Support/tape/models/
```

| Model | Size | Notes |
|---|---|---|
| tiny | ~75 MB | Fastest, lightest |
| base | ~142 MB | Better balance |
| small | ~466 MB | Better accuracy |
| medium | ~1.5 GB | High accuracy |
| large-v3 | ~3.1 GB | Highest accuracy, slowest |

## Current State

This is a focused macOS utility, not a giant platform.

That means:

- the app is intentionally small
- the core loop matters more than feature count
- the GitHub repo should read like a sharp tool, not a startup pitch deck

## License

MIT
