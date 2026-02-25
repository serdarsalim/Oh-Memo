import Domain
import Foundation

public struct FileSystemRecordingScanner: RecordingScanner, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func listRecordings(in folderURL: URL) async throws -> [RecordingFile] {
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        let files = urls
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .compactMap { url -> RecordingFile? in
                let values = try? url.resourceValues(forKeys: resourceKeys)
                guard values?.isRegularFile != false else {
                    return nil
                }

                let fileName = url.deletingPathExtension().lastPathComponent
                let modifiedAt = values?.contentModificationDate ?? .distantPast
                let recordedAt = FilenameDateParser.parse(fileName: fileName)

                return RecordingFile(
                    fileURL: url,
                    fileName: fileName,
                    recordedAt: recordedAt,
                    fileModifiedAt: modifiedAt
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.effectiveDate
                let right = rhs.effectiveDate
                if left == right {
                    return lhs.fileName > rhs.fileName
                }
                return left > right
            }

        return files
    }
}

enum FilenameDateParser {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd HHmmss"
        return formatter
    }()

    static func parse(fileName: String) -> Date? {
        guard fileName.count >= 15 else {
            return nil
        }

        let prefix = String(fileName.prefix(15))
        return formatter.date(from: prefix)
    }
}
