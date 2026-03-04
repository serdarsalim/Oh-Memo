# VoiceMemoTranscriptsApp - Agent Quickstart

## Project Summary
- macOS SwiftUI app that scans a selected recordings folder, extracts Apple Voice Memo transcripts from `.m4a`, and lets users search transcript content, copy, and export.
- Architecture is modular (Swift Package targets): `AppShell`, `Domain`, `Data`, `Platform`, `FeatureRecordings`, `FeatureTranscriptViewer`, `FeatureExport`.
- Current UX priorities: fast scanning, reliable dark/light appearance, clean split-view layout, and frictionless copy/export workflow.

## User Collaboration Rules (Important)
- If the user says **"ideate"**: brainstorm only, discuss options and tradeoffs, do **not** execute changes yet.
- Execute changes only after the user says **"go"** for that ideation thread.
- For clear direct instructions outside ideation (example: "fix sidebar width"), execute immediately without waiting for "go".

## How To Run
- Build: `swift build`
- Run app: `swift run VoiceMemoTranscriptsApp`

## Core Flow
1. User selects recordings folder (saved via bookmark).
2. App scans `.m4a` files.
3. App runs extractor script per file and parses transcript JSON/text.
4. Sidebar lists recordings/snippets; search filters by transcript content.
5. Detail pane shows transcript; footer supports copy/export actions.

## Key Files
- App composition:
  - `Package.swift`
  - `Sources/AppShell/VoiceMemoTranscriptsApp.swift`
  - `Sources/AppShell/RootView.swift`
  - `Sources/AppShell/AppModel.swift`
  - `Sources/AppShell/AppearanceMode.swift`

- Domain layer:
  - `Sources/Domain/Models.swift`
  - `Sources/Domain/Protocols.swift`
  - `Sources/Domain/UseCases.swift`

- Data layer:
  - `Sources/Data/FileSystemRecordingScanner.swift`
  - `Sources/Data/ScriptTranscriptExtractor.swift`
  - `Sources/Data/UserDefaultsFolderBookmarkStore.swift`

- Platform wrappers:
  - `Sources/Platform/FolderPickerClient.swift`
  - `Sources/Platform/ClipboardClient.swift`
  - `Sources/Platform/FileSaveClient.swift`

- Feature UI modules:
  - `Sources/FeatureRecordings/RecordingsSidebarView.swift`
  - `Sources/FeatureTranscriptViewer/TranscriptDetailView.swift`
  - `Sources/FeatureExport/ExportActionBar.swift`

- Extractor scripts:
  - `extract-apple-voice-memos-transcript` (root script)
  - `Sources/AppShell/Resources/extract-apple-voice-memos-transcript` (bundled copy used by app)
  - `extract_all_voice_memos.sh` (batch helper)

## Known Gotchas
- If scan appears stuck, inspect `Sources/Data/ScriptTranscriptExtractor.swift` first (process timeout/termination handling).
- macOS permissions and security-scoped bookmarks affect folder access.
- Keep UI bars one-line and avoid overlays that obscure sidebar content.

## Implementation Expectations
- Keep changes modular by target boundary.
- Prefer transcript-content search over filename-based search.
- Validate with `swift build` after edits.
- Release packaging rule: whenever pushing a new app update, also rebuild and replace the distributable zip.
  - Build zip with `./build-app.sh` (produces `dist/oh-memo-macos.zip`).
  - Upload and replace release asset with `gh release upload v0.1.0 dist/oh-memo-macos.zip --clobber`.
