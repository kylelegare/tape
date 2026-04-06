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

Most transcription tools do a lot. Dashboards, coaching tools, integrations, cloud sync... and then the subscription fee to hold it all together.
tape doesn't do most of that. It records your meeting, transcribes it locally with Whisper, and saves a Markdown file to your machine. That's the whole thing.
The idea is that you've already got LLMs, agents, and a notes workflow you like. tape just gets the transcript out of the way so those tools can do their thing. No account, no subscription, no cloud everything stays on your machine.

1. Click **Record**
2. Talk
3. Click **Stop**
4. Get a `.md` file

## What it does

- Lives in the **macOS menu bar** — one click to start
- Records from your mic, transcribes locally with Whisper
- Filters out hallucinated filler text that Whisper generates in silent gaps
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

### Just want the app?

1. Go to [Releases](https://github.com/kylelegare/tape/releases) and download `Tape.zip`
2. Unzip it, drag `Tape.app` to your `/Applications` folder
3. Right-click → Open the first time (macOS will ask if you trust it — say yes)
4. Tape appears in your menu bar as a cassette icon

That's it. No installer, no setup.

> First time you use it, it'll ask for mic permission and download a Whisper model (~75 MB for the default). Both happen once.

### Want to build from source?

You'll need macOS 15+ and Xcode 16+.

```bash
git clone https://github.com/kylelegare/tape
open tape/Tape.xcodeproj
```

Hit Run in Xcode and it'll appear in the menu bar.

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
