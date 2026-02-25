import AppKit
import Foundation

@MainActor
public struct ClipboardClient {
    public init() {}

    public func setString(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
