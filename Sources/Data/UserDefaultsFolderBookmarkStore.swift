import Domain
import Foundation

public final class UserDefaultsFolderBookmarkStore: FolderBookmarkStore, @unchecked Sendable {
    private let bookmarkKey: String
    private let pathKey: String
    private let defaults: UserDefaults

    public init(
        bookmarkKey: String = "voiceMemo.folderBookmark",
        pathKey: String = "voiceMemo.folderPath",
        defaults: UserDefaults = .standard
    ) {
        self.bookmarkKey = bookmarkKey
        self.pathKey = pathKey
        self.defaults = defaults
    }

    public func save(folderURL: URL) throws {
        let data = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(folderURL.path, forKey: pathKey)
    }

    public func resolveSavedFolderURL() throws -> URL? {
        if let data = defaults.data(forKey: bookmarkKey) {
            do {
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
                defaults.set(url.path, forKey: pathKey)

                return url
            } catch {
                if let fallback = resolvePathFallback() {
                    return fallback
                }
                throw error
            }
        }

        return resolvePathFallback()
    }

    public func clear() throws {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: pathKey)
    }

    private func resolvePathFallback() -> URL? {
        guard let savedPath = defaults.string(forKey: pathKey), !savedPath.isEmpty else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: savedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        return URL(fileURLWithPath: savedPath, isDirectory: true)
    }
}
