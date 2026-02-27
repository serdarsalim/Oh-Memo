import AppKit
import Foundation

@MainActor
public struct FolderPickerClient {
    public init() {}

    public func pickFolder(initialURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
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
