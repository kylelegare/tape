<p align="center">
  <img src="assets/tape-hero.png" alt="tape — Lightweight Meeting Recorder" width="500">
</p>

<p align="center">
  <strong>Local-first voice recorder for macOS</strong><br>
  Record, transcribe, and save as plain Markdown files.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_15+-blue?logo=apple&logoColor=white" alt="macOS 15+">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/transcription-WhisperKit-green" alt="WhisperKit">
  <img src="https://img.shields.io/github/license/kylelegare/tape" alt="License">
</p>

---

## Why this exists

Most transcription tools do a lot. Dashboards, coaching tools, integrations, cloud sync, and a subscription to hold it all together.

tape doesn't do most of that. It records, transcribes locally, and saves a Markdown file to your machine. That's the whole thing.

Get a transription of any calls, or meetings you're having. You can even just hit record and brain dump, send a note to yourself. It all ends up as a mark down file saved locally in a folder. Your agents can grab that file and do whatever with it. No account, no subscription, no cloud. 

## What it does

- Lives in the **macOS menu bar** — out of the way until you need it
- Hit Record, hit Stop — that's it
- Transcribes offline using [WhisperKit](https://github.com/argmaxinc/WhisperKit) — no audio ever leaves your Mac
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

1. Go to [Releases](https://github.com/kylelegare/tape/releases) and download `tape.zip`
2. Unzip it and drag `Tape.app` to your Applications folder
3. Right-click → **Open** on first launch — macOS will warn you it's not from the App Store, just click Open to proceed. After that it opens normally.

The first time you record, tape will ask for microphone permission. The first time you transcribe, it downloads the Whisper `tiny` model (~75 MB) automatically — this only happens once. You can switch to a more accurate model in Settings (we recommend `medium`).

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

tape transcribes the audio in the background and saves a `.md` file to your output folder. You can start a new recording immediately — you don't have to wait for transcription to finish.

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

tape defaults to `tiny` for fast transcription. For better accuracy — especially with accents, names, or technical terms — switch to `medium`. The model downloads once in the background when you change it.

| Model | Size | Notes |
|---|---|---|
| tiny | ~75 MB | Default. Fast, good for clear audio |
| base | ~142 MB | Slightly better accuracy |
| small | ~466 MB | Noticeably better |
| **medium** | **~1.5 GB** | **Recommended for best everyday accuracy** |
| large-v3 | ~3.1 GB | Highest quality, slowest |

## Privacy

tape is designed around not needing to trust it:

- **No cloud.** Audio and transcripts never leave your machine. Transcription runs entirely offline.
- **No account.** Nothing to sign up for.
- **No background activity.** tape only records when you explicitly hit Record. It does nothing when idle.
- **Mic permission** is handled by macOS. You can revoke it anytime in System Settings → Privacy & Security → Microphone.
- **Open source.** You can read exactly what it does.

## Intentionally simple

tape won't grow into a platform. No roadmap toward team plans, analytics, or AI meeting assistants. It records, transcribes, saves a file. That's the whole thing.

## License

MIT
