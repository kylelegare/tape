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

Most transcription tools do a lot. Dashboards, coaching tools, integrations, cloud sync — and a subscription to hold it all together.

tape doesn't do most of that. It records your meeting, transcribes it locally with Whisper, and saves a Markdown file to your machine. That's the whole thing.

The idea is that you've already got LLMs, agents, and a notes workflow you like. tape just gets the transcript out of the way so those tools can do their thing. No account, no subscription, no cloud — everything stays on your machine.

## What it does

- Lives in the **macOS menu bar** — out of the way until you need it
- Records from your mic, transcribes locally with [Whisper](https://github.com/openai/whisper)
- **Smart detection** — recognizes when Zoom, Teams, Slack, Chrome, and other meeting apps start using your mic, and prompts you to record
- Ignores voice dictation tools (like Monologue) so they don't trigger false alerts
- Filters out hallucinated filler text that Whisper generates during silent gaps
- Saves each recording as a **Markdown file** with YAML frontmatter
- Nothing leaves your machine — no cloud, no telemetry, no analytics

## Example output

Every recording becomes a plain text file you own.

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



## Transcript

[00:00] Kyle: ...
```

## Getting started

### Download (easiest)

1. Go to [Releases](https://github.com/kylelegare/tape/releases) and download `Tape.zip`
2. Unzip it and drag `Tape.app` to your Applications folder
3. Right-click → **Open** on first launch — macOS will warn you it's not from the App Store, just click Open to proceed. After that it opens normally.

tape will ask for microphone permission the first time you record, and download a small Whisper model (~75 MB) the first time you transcribe. Both happen once.

---

### Build from source

You'll need [Xcode](https://developer.apple.com/xcode/) (Apple's free developer tool) and macOS 15+.

```bash
git clone https://github.com/kylelegare/tape
open tape/Tape.xcodeproj
```

Press **⌘R** or the Play button to build and run.

> **Note:** mic detection requires a signed build. If you're running an unsigned debug build, detection may not work correctly — use Download above if you just want to use the app.

## How it works

**Manual:** click the cassette icon in your menu bar → hit Record → hit Stop when you're done.

**Auto-detection:** tape watches which apps are using your microphone at the process level. When a known meeting app (Zoom, Teams, Slack, etc.) picks up the mic, it sends you a notification with a Record button. No polling, no calendar access needed — it just watches what's actually happening on your machine.

When you stop recording, tape transcribes locally and saves a `.md` file to your output folder.

## Settings

| Tab | Setting | Default | What it does |
|---|---|---|---|
| General | Output folder | `~/Documents/tape/` | Where `.md` files are saved |
| General | Launch at login | Off | Start tape when you log in |
| Recording | Your name | — | Labels your speaker in the transcript |
| Recording | Whisper model | `tiny` | Larger = more accurate, slower |
| Recording | Min recording | `5s` | Recordings shorter than this are discarded |
| Recording | Custom vocabulary | — | Bias transcription toward names and terms |
| Detection | Meeting apps | 16 defaults on | Toggle which apps can trigger recording |
| Detection | Also detected | — | Shows any other apps tape has seen using your mic |

## Whisper models

Models download on first use to `~/Library/Application Support/tape/models/`.

| Model | Size | Notes |
|---|---|---|
| tiny | ~75 MB | Fastest, good for most uses |
| base | ~142 MB | Slightly better accuracy |
| small | ~466 MB | Noticeably better |
| medium | ~1.5 GB | High accuracy |
| large-v3 | ~3.1 GB | Best quality, slowest |

## Privacy

tape is designed around not needing to trust it:

- **No cloud.** Audio and transcripts never leave your machine.
- **No account.** Nothing to sign up for.
- **No background recording.** tape only records when you explicitly hit Record or confirm a notification prompt. It watches which apps are using your mic — not what they're saying.
- **Mic permission** is handled by macOS. You can revoke it anytime in System Settings → Privacy & Security → Microphone.
- **Open source.** You can read exactly what it does.

## Intentionally simple

tape won't grow into a platform. No roadmap toward team plans, analytics, or AI meeting assistants. It records, transcribes, saves a file. That's the whole thing.

## License

MIT
