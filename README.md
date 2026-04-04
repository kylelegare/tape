<p align="center">
  <img src="assets/tape-hero.png" alt="tape — Lightweight Meeting Recorder" width="500">
</p>

<p align="center">
  <strong>Local-first meeting recorder for macOS</strong><br>
  Record, transcribe, and save meetings as plain Markdown files.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_15+-blue?logo=apple&logoColor=white" alt="macOS 15+">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/whisper-local_transcription-green" alt="Whisper">
  <img src="https://img.shields.io/github/license/kylelegare/tape" alt="License">
</p>

---

## Why this exists

Meeting transcription tools have gotten expensive and bloated. They start simple — record, transcribe — but SaaS needs to grow, so they bolt on team features, dashboards, AI summaries, coaching tools, and integrations you never asked for. The price goes up. The complexity goes up. And at the end of the day, all you actually needed was the transcript.

That's it. A transcript is just data. Your agents, your LLMs, your own notes workflow — those do the real work. You don't need a platform sitting between you and a text file.

**tape** is the dumb, cheap alternative. It records, transcribes locally with Whisper, and drops a Markdown file on your machine. No account, no subscription, no cloud.

1. Click **Record**
2. Talk
3. Click **Stop**
4. Get a `.md` file

## What it does

- Lives in the **macOS menu bar** — one click to start
- Records from your mic, transcribes locally with Whisper
- Saves each recording as a **Markdown file** with YAML frontmatter
- Nothing leaves your machine — no cloud, no telemetry
- Output is just text — easy to grep, sync, or hand to an agent

## Example output

Every recording becomes a file you own.

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

## Getting started

### Requirements

- macOS 15+
- Xcode 16+

### Build from source

```bash
open Tape.xcodeproj
```

Run the `Tape` scheme. The app appears in the menu bar as a cassette icon.

For a release build:

```bash
xcodebuild -project Tape.xcodeproj -scheme Tape -configuration Release build
```

## Settings

| Setting | Default | Description |
|---|---|---|
| Output folder | `~/Documents/tape/` | Where `.md` files are saved |
| Launch at login | Off | Start tape when you log in |
| Your name | — | Labels your speaker name in transcripts |
| Whisper model | `tiny` | Downloads on first use |
| Min recording | `5s` | Short recordings are discarded |
| Custom vocabulary | — | Bias transcription toward names and terms |

## Whisper models

Models download on first use to `~/Library/Application Support/tape/models/`.

| Model | Size | Notes |
|---|---|---|
| tiny | ~75 MB | Fastest, lightest |
| base | ~142 MB | Better balance |
| small | ~466 MB | Better accuracy |
| medium | ~1.5 GB | High accuracy |
| large-v3 | ~3.1 GB | Highest accuracy, slowest |

## Intentionally simple

**tape** won't grow into a platform. There's no roadmap toward team plans, analytics, or AI meeting assistants. It records, it transcribes, it saves a file. That's the whole thing.

## License

MIT
