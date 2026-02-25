import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct FileSaveClient {
    public init() {}

    public func save(data: Data, suggestedFileName: String, contentType: UTType) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let destinationURL = panel.url else {
            return nil
        }

        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }
}
