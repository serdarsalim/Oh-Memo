import Domain
import Foundation

public final class UserDefaultsFolderBookmarkStore: FolderBookmarkStore, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults

    public init(key: String = "voiceMemo.folderBookmark", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func save(folderURL: URL) throws {
        let data = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: key)
    }

    public func resolveSavedFolderURL() throws -> URL? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try save(folderURL: url)
        }

        return url
    }

    public func clear() throws {
        defaults.removeObject(forKey: key)
    }
}
