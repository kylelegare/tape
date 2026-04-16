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
  <img src="https://img.shields.io/badge/transcription-WhisperKit-green" alt="WhisperKit">
  <img src="https://img.shields.io/github/license/kylelegare/tape" alt="License">
</p>

---

## Why this exists

Most transcription tools do a lot. Dashboards, coaching tools, integrations, cloud sync — and a subscription to hold it all together.

tape doesn't do most of that. It records your meeting, transcribes it locally, and saves a Markdown file to your machine. That's the whole thing.

The idea is that you've already got LLMs, agents, and a notes workflow you like. tape just gets the transcript out of the way so those tools can do their thing. No account, no subscription, no cloud — everything stays on your machine.

## What it does

- Lives in the **macOS menu bar** — out of the way until you need it
- Hit Record, hit Stop — that's it
- Transcribes locally using [WhisperKit](https://github.com/argmaxinc/WhisperKit) — runs on your Neural Engine, never touches the network
- Saves each recording as a **Markdown file** with YAML frontmatter
- Everything stays on your machine

## Example output

Every recording becomes a plain text file you own.

```markdown
---
title: "Apr 16, 2:30 PM"
date: 2026-04-16
time: 14:30
duration: 47min
speakers:
  - Kyle
partial: false
---

## Context



## Transcript

**[0:00] Kyle:** ...

**[1:23] Others:** ...
```

## Getting started

### Download (easiest)

1. Go to [Releases](https://github.com/kylelegare/tape/releases) and download `Tape.zip`
2. Unzip it and drag `Tape.app` to your Applications folder
3. Right-click → **Open** on first launch — macOS will warn you it's not from the App Store, just click Open to proceed. After that it opens normally.

tape will ask for microphone permission the first time you record, and download a Whisper model the first time you transcribe. Both happen once.

---

### Build from source

You'll need [Xcode](https://developer.apple.com/xcode/) and macOS 15+.

```bash
git clone https://github.com/kylelegare/tape
open tape/Tape.xcodeproj
```

Press **⌘R** or the Play button to build and run.

## How it works

Click the cassette icon in your menu bar → hit **Record** → hit **Stop** when you're done.

tape transcribes the audio locally using WhisperKit (Apple Neural Engine) and saves a `.md` file to your output folder. State returns to idle immediately after you stop, so you can start the next recording while the previous one is still transcribing.

## Settings

| Tab | Setting | Default | What it does |
|---|---|---|---|
| General | Output folder | `~/Documents/tape/` | Where `.md` files are saved |
| General | Launch at login | Off | Start tape when you log in |
| Recording | Your name | — | Labels your speaker in the transcript |
| Recording | Whisper model | `tiny` | Larger = more accurate, slower to transcribe |
| Recording | Min recording | `5s` | Recordings shorter than this are discarded |
| Vocabulary | Custom vocabulary | — | Fix common transcription mistakes for names and terms |

## Whisper models

Change the model anytime in **Settings → Recording → Whisper model**. The new model downloads automatically when you next transcribe.

| Model | Size | Notes |
|---|---|---|
| tiny | ~75 MB | Fastest, good for most uses |
| base | ~142 MB | Slightly better accuracy |
| small | ~466 MB | Noticeably better |
| medium | ~1.5 GB | High accuracy |
| large-v3 | ~3.1 GB | Best quality, slowest |

## Privacy

tape is designed around not needing to trust it:

- **No cloud.** Audio and transcripts never leave your machine. Transcription runs entirely on-device via WhisperKit.
- **No account.** Nothing to sign up for.
- **No background activity.** tape only records when you explicitly hit Record. It does nothing when idle.
- **Mic permission** is handled by macOS. You can revoke it anytime in System Settings → Privacy & Security → Microphone.
- **Open source.** You can read exactly what it does.

## Intentionally simple

tape won't grow into a platform. No roadmap toward team plans, analytics, or AI meeting assistants. It records, transcribes, saves a file. That's the whole thing.

## License

MIT
