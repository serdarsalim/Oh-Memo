import Data
import Domain
import Platform
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct VoiceMemoTranscriptsApp: App {
    private let model: AppModel
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif

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
        WindowGroup("Oh Memo") {
            RootView(model: model)
                .frame(minWidth: 1260, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}

#if os(macOS)
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }
}
#endif
