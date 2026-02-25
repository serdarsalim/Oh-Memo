import Data
import Domain
import Platform
import SwiftUI

@main
struct VoiceMemoTranscriptsApp: App {
    private let model: AppModel

    init() {
        let scanner = FileSystemRecordingScanner()
        let extractor = ScriptTranscriptExtractor()
        let scanUseCase = ScanRecordingsUseCase(scanner: scanner, extractor: extractor)

        self.model = AppModel(
            scanUseCase: scanUseCase,
            searchUseCase: SearchTranscriptsUseCase(),
            exportUseCase: ExportTranscriptsUseCase(),
            bookmarkStore: UserDefaultsFolderBookmarkStore(),
            folderPicker: FolderPickerClient(),
            clipboard: ClipboardClient(),
            saveClient: FileSaveClient()
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
