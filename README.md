# Oh Memo

Oh Memo is a macOS app that helps you organize, search, and act on your Apple Voice Memos transcripts.

If Voice Memos feels too basic for serious follow-up work, this app gives you a focused workspace for transcript management.

## What You Can Do

- See your recordings in a clean, searchable sidebar.
- Rename recordings with your own titles (saved between restarts).
- Read transcripts with inline audio playback.
- Auto-detect new recordings from your folder.
- Copy a single transcript or export all transcripts.
- Run AI analysis on a selected transcript:
  - Summary
  - Action items
  - Conversion sentiment score
  - What went well / what to improve
- Customize the AI prompt and keep your prompt saved across sessions.

## Why People Use It

- Turn long calls into clear next steps.
- Find key conversations fast by keyword.
- Keep transcript organization separate from the Voice Memos UI.
- Get a lead-quality style summary quickly without manual review.

## Quick Start

1. Launch the app.
2. Select your Voice Memos `Recordings` folder.
3. Wait for initial scan (first set loads first, then the rest continues in background).
4. Click any transcript in the sidebar to open it.
5. Use the floating right-side toggle to switch between:
   - Transcript view
   - AI Assistant view

## AI Assistant

- Add your OpenAI API key from the gear icon in the footer.
- Switch to AI view; analysis auto-runs for that transcript if no cached analysis exists yet.
- Use:
  - Copy icon to copy AI output
  - Refresh icon to re-analyze
  - Prompt icon to edit your analysis prompt
- AI results persist across app restarts.

## Export and Copy

From the export icon menu in the footer, you can:

- Copy all transcripts to clipboard
- Download all transcripts as `.txt`

## Build and Run (No Xcode Required)

From this folder:

```bash
swift build
swift run VoiceMemoTranscriptsApp
```

To build a standalone app bundle:

```bash
./build-app.sh
open dist/VoiceMemoTranscriptsApp.app
```

## Folder to Select

Typical path:

`~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`

## Privacy Note

- Transcript data stays on your machine unless you explicitly use AI analysis.
- AI analysis sends selected transcript text to OpenAI API.
- API key is managed from app settings.

## License

This project is licensed under the GNU Affero General Public License v3.0.
See [LICENSE](./LICENSE).
