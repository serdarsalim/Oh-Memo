import AppKit
import Foundation

@MainActor
public struct FolderPickerClient {
    public init() {}

    public func pickFolder(initialURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Recordings Folder"
        panel.message = "Select the Voice Memos Recordings folder, then click Select Recordings Folder."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Recordings Folder"
        panel.directoryURL = initialURL

        let response = panel.runModal()
#if os(macOS)
        NSApp.activate(ignoringOtherApps: true)
#endif
        guard response == .OK else {
            return nil
        }

        return panel.urls.first
    }
}
