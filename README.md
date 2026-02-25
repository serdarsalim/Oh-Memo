# Voice Memo Transcripts

This repository now includes:
1. The original transcript extractor script for Apple Voice Memos `.m4a` files.
2. A modular macOS SwiftUI app scaffold that uses that script and provides content search, copy, and export.

## Original CLI Extractor

```bash
./extract-apple-voice-memos-transcript [--text|--json|--raw] <filename>
```

Voice Memos recordings are typically stored at:
`~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`

## macOS App Scaffold

The app is implemented as a Swift package with modular targets:

- `AppShell`: app entry point and composition root.
- `Domain`: models, protocols, use cases.
- `Data`: folder scanning, bookmark persistence, script-backed transcript extraction.
- `Platform`: macOS adapters (`NSOpenPanel`, clipboard, save panel).
- `FeatureRecordings`: sidebar list and content search UI.
- `FeatureTranscriptViewer`: transcript detail and inspector UI.
- `FeatureExport`: copy/export action bar and scan summary.

### Implemented UX

- First-run folder selection (with persisted bookmark).
- Scan/rescan `.m4a` files in selected folder.
- Search by transcript content (not filename).
- Sort by newest/oldest/longest/recently scanned.
- Appearance mode picker: `System`, `Light`, `Dark` (persisted).
- Copy current transcript.
- Copy all transcripts.
- Export `.txt` and `.json`.
- Failed-file sheet with error details.

## How to Run in Xcode

1. Open this folder as a Swift package in Xcode.
2. Select executable target `VoiceMemoTranscriptsApp`.
3. Run the app.

The extractor script is bundled at:
`Sources/AppShell/Resources/extract-apple-voice-memos-transcript`

The app also checks `VOICE_MEMO_EXTRACTOR_PATH` env var first. If needed, set it in your Xcode Run scheme to point to a script path on disk.

## Notes

- App Store-safe path handling is implemented with user-selected folder access instead of hardcoded Voice Memos container paths.
- The UI is designed around transcript content search and date-based sort because Voice Memo filenames are opaque IDs.
