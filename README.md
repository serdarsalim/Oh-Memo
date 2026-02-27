# Transcript Manager

Transcript Manager is a macOS SwiftUI app for browsing Apple Voice Memos transcripts from `.m4a` recordings.

It scans a user-selected Voice Memos folder, extracts transcript payloads from each file, and gives you a fast sidebar + detail workflow for searching, reading, copying, and exporting transcripts.

## What This App Does

- Loads a recordings folder using a persisted security-scoped bookmark.
- Scans `.m4a` files and extracts transcript data via the bundled extractor script.
- Watches the folder for file changes and auto-rescans when new recordings appear.
- Shows a searchable/sortable recording list in the sidebar.
- Displays transcript detail with:
  - Editable recording description/title (persisted between app restarts)
  - Inline audio playback (play/pause, seek slider, elapsed/total time)
  - Copy transcript action
- Prefers saved description text in the sidebar row title when available.
- Exports merged transcripts as `.txt` or `.json`.
- Shows extraction failures in a dedicated sheet.

## Transcript Rendering

The app tries to preserve Apple transcript formatting when available in the transcript payload.
If the payload has no useful structure, it falls back to readable sentence/paragraph formatting.

## Project Structure

- `Sources/AppShell`: app composition, root view, app model/state
- `Sources/Domain`: core models/protocols/use cases
- `Sources/Data`: folder scanner + script transcript extraction + bookmark persistence
- `Sources/Platform`: macOS wrappers (open panel, save panel, clipboard)
- `Sources/FeatureRecordings`: sidebar/search/list UI
- `Sources/FeatureTranscriptViewer`: transcript detail/player/inspector UI
- `Sources/FeatureExport`: footer export/status action bar

## Run

```bash
swift build
swift run VoiceMemoTranscriptsApp
```

## Build Standalone App (No Xcode)

Create a double-clickable app bundle in `dist/`:

```bash
./build-app.sh
open dist/VoiceMemoTranscriptsApp.app
```

## Extractor CLI

You can run the original extractor script directly:

```bash
./extract-apple-voice-memos-transcript [--text|--json|--raw] <filename>
```

The app uses the bundled copy at:

`Sources/AppShell/Resources/extract-apple-voice-memos-transcript`

## Typical Voice Memos Folder

`~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`

## License

This project is licensed under the GNU Affero General Public License v3.0.
See [LICENSE](./LICENSE).
