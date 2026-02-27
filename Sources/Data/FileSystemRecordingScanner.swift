import Domain
import Foundation
#if os(macOS)
import AVFoundation
import CoreServices
#endif

public struct FileSystemRecordingScanner: RecordingScanner, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func listRecordings(in folderURL: URL) async throws -> [RecordingFile] {
        let recordingsFolderURL = resolveRecordingsFolderURL(from: folderURL)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let urls = try fileManager.contentsOfDirectory(
            at: recordingsFolderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var discoveredFiles = urls
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .compactMap { url -> DiscoveredRecordingFile? in
                let values = try? url.resourceValues(forKeys: resourceKeys)
                guard values?.isRegularFile != false else {
                    return nil
                }

                let fileName = url.deletingPathExtension().lastPathComponent
                let modifiedAt = values?.contentModificationDate ?? .distantPast
                let recordedAt = FilenameDateParser.parse(fileName: fileName)

                return DiscoveredRecordingFile(
                    fileURL: url,
                    fileName: fileName,
                    recordedAt: recordedAt ?? modifiedAt,
                    fileModifiedAt: modifiedAt,
                    originalRecordedAt: recordedAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.recordedAt == rhs.recordedAt {
                    return lhs.fileName > rhs.fileName
                }
                return lhs.recordedAt > rhs.recordedAt
            }

        if let activeBaseNames = VoiceMemosActiveRecordingFilter.activeRecordingBaseNames(
            in: recordingsFolderURL,
            availableBaseNames: Set(discoveredFiles.map(\.fileName))
        ) {
            discoveredFiles = discoveredFiles.filter { activeBaseNames.contains($0.fileName) }
        }

        let titlesByBaseName = VoiceMemosActiveRecordingFilter.voiceMemoTitles(
            in: recordingsFolderURL,
            availableBaseNames: Set(discoveredFiles.map(\.fileName))
        )

        let files = discoveredFiles.map { file in
            let titleFromMetadata = VoiceMemoFileTitleExtractor.extractTitle(from: file.fileURL)
            return RecordingFile(
                fileURL: file.fileURL,
                fileName: file.fileName,
                voiceMemoTitle: titlesByBaseName[file.fileName] ?? titleFromMetadata,
                recordedAt: file.originalRecordedAt,
                fileModifiedAt: file.fileModifiedAt
            )
        }

        return files
    }

    private func resolveRecordingsFolderURL(from baseFolderURL: URL) -> URL {
        if containsM4AFiles(in: baseFolderURL) {
            return baseFolderURL
        }

        let recordingsSubfolderURL = baseFolderURL.appendingPathComponent("Recordings", isDirectory: true)
        if containsM4AFiles(in: recordingsSubfolderURL) {
            return recordingsSubfolderURL
        }

        return baseFolderURL
    }

    private func containsM4AFiles(in folderURL: URL) -> Bool {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return urls.contains { $0.pathExtension.lowercased() == "m4a" }
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

private struct DiscoveredRecordingFile {
    let fileURL: URL
    let fileName: String
    let recordedAt: Date
    let fileModifiedAt: Date
    let originalRecordedAt: Date?
}

private enum VoiceMemosActiveRecordingFilter {
    static func activeRecordingBaseNames(
        in recordingsFolderURL: URL,
        availableBaseNames: Set<String>
    ) -> Set<String>? {
        guard !availableBaseNames.isEmpty else { return nil }
        let matcher = RecordingBaseNameMatcher(availableBaseNames: availableBaseNames)

        let databaseURLs = candidateDatabaseURLs(near: recordingsFolderURL)
        var aggregatedActiveBaseNames = Set<String>()
        var foundUsableMetadataSource = false

        for databaseURL in databaseURLs where FileManager.default.fileExists(atPath: databaseURL.path) {
            let tableNames = loadRecordingLikeTableNames(from: databaseURL)
            for tableName in tableNames {
                let tableColumns = loadColumns(from: databaseURL, tableName: tableName)
                let deletionColumns = tableColumns.filter { isDeletionColumnName($0) }
                guard !deletionColumns.isEmpty else {
                    continue
                }

                let textColumns = tableColumns.filter {
                    !deletionColumns.contains($0) && isPotentialRecordingReferenceColumn($0)
                }
                guard !textColumns.isEmpty else {
                    continue
                }

                let selectedColumns = orderedUnique(textColumns + deletionColumns)
                guard let rows = loadRows(from: databaseURL, tableName: tableName, columns: selectedColumns) else {
                    continue
                }

                foundUsableMetadataSource = true
                let deletionColumnSet = Set(deletionColumns)

                for row in rows {
                    let isDeleted = row.contains { column, value in
                        deletionColumnSet.contains(column) && isTruthy(value)
                    }
                    if isDeleted {
                        continue
                    }

                    for (column, value) in row where !deletionColumnSet.contains(column) {
                        let extractedNames = matcher.extractMatchingBaseNames(from: value)
                        for baseName in extractedNames where availableBaseNames.contains(baseName) {
                            aggregatedActiveBaseNames.insert(baseName)
                        }
                    }
                }
            }
        }

        guard foundUsableMetadataSource else {
            return nil
        }

        return aggregatedActiveBaseNames.isEmpty ? nil : aggregatedActiveBaseNames
    }

    static func voiceMemoTitles(
        in recordingsFolderURL: URL,
        availableBaseNames: Set<String>
    ) -> [String: String] {
        guard !availableBaseNames.isEmpty else { return [:] }
        let matcher = RecordingBaseNameMatcher(availableBaseNames: availableBaseNames)

        let databaseURLs = candidateDatabaseURLs(near: recordingsFolderURL)
        var titlesByBaseName: [String: String] = [:]

        for databaseURL in databaseURLs where FileManager.default.fileExists(atPath: databaseURL.path) {
            let tableNames = loadRecordingLikeTableNames(from: databaseURL)
            for tableName in tableNames {
                let tableColumns = loadColumns(from: databaseURL, tableName: tableName)
                let referenceColumns = tableColumns.filter { isPotentialRecordingReferenceColumn($0) }
                let titleColumns = tableColumns.filter { isPotentialTitleColumn($0) }
                guard !referenceColumns.isEmpty, !titleColumns.isEmpty else {
                    continue
                }

                let selectedColumns = orderedUnique(referenceColumns + titleColumns)
                guard let rows = loadRows(from: databaseURL, tableName: tableName, columns: selectedColumns) else {
                    continue
                }

                let titleColumnSet = Set(titleColumns)
                for row in rows {
                    let baseNames: Set<String> = row.reduce(into: Set<String>()) { names, pair in
                        guard !titleColumnSet.contains(pair.column) else { return }
                        names.formUnion(matcher.extractMatchingBaseNames(from: pair.value))
                    }

                    guard !baseNames.isEmpty else { continue }

                    let titleCandidates = row
                        .filter { titleColumnSet.contains($0.column) }
                        .map(\.value)
                        .compactMap(cleanTitle)

                    guard let title = titleCandidates.first(where: {
                        !matcher.looksLikeRecordingIdentifier($0)
                    }) else {
                        continue
                    }

                    for baseName in baseNames where titlesByBaseName[baseName] == nil {
                        titlesByBaseName[baseName] = title
                    }
                }
            }
        }

        return titlesByBaseName
    }

    private static func candidateDatabaseURLs(near recordingsFolderURL: URL) -> [URL] {
        let parentFolderURL = recordingsFolderURL.deletingLastPathComponent()
        let maybeContainerRootURL = recordingsFolderURL.lastPathComponent == "Recordings"
            ? parentFolderURL
            : recordingsFolderURL

        let directCandidates = [
            recordingsFolderURL.appendingPathComponent("CloudRecordings.db"),
            recordingsFolderURL.appendingPathComponent("Recordings.db"),
            recordingsFolderURL.appendingPathComponent("Recordings.sqlite"),
            parentFolderURL.appendingPathComponent("CloudRecordings.db"),
            parentFolderURL.appendingPathComponent("Recordings.db"),
            parentFolderURL.appendingPathComponent("Recordings.sqlite"),
            maybeContainerRootURL.appendingPathComponent("CloudRecordings.db"),
            maybeContainerRootURL.appendingPathComponent("Recordings.db"),
            maybeContainerRootURL.appendingPathComponent("Recordings.sqlite")
        ]

        let discovered = discoverLikelyDatabaseURLs(in: recordingsFolderURL, maxDepth: 2)
            + discoverLikelyDatabaseURLs(in: parentFolderURL, maxDepth: 2)
            + discoverLikelyDatabaseURLs(in: maybeContainerRootURL, maxDepth: 2)

        return orderedUniqueURLs(directCandidates + discovered)
    }

    private static func discoverLikelyDatabaseURLs(in rootURL: URL, maxDepth: Int) -> [URL] {
        guard maxDepth >= 0 else { return [] }
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let relativeDepth = fileURL.pathComponents.count - rootURL.pathComponents.count
            if relativeDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]) else {
                continue
            }
            if values.isDirectory == true {
                continue
            }

            let lowercasedName = fileURL.lastPathComponent.lowercased()
            let extensionValue = fileURL.pathExtension.lowercased()
            guard extensionValue == "db" || extensionValue == "sqlite" || extensionValue == "sqlite3" else {
                continue
            }

            if lowercasedName.contains("record") || lowercasedName.contains("voice") || lowercasedName.contains("cloud") {
                results.append(fileURL)
            }
        }
        return results
    }

    private static func loadRecordingLikeTableNames(from databaseURL: URL) -> [String] {
        let query = "SELECT name FROM sqlite_master WHERE type='table';"
        guard let output = runSQLite(databaseURL: databaseURL, query: query) else {
            return []
        }

        return output
            .split(separator: "\n")
            .map(String.init)
            .filter {
                let uppercased = $0.uppercased()
                return uppercased.contains("RECORDING") || uppercased.contains("MEMO")
            }
    }

    private static func loadColumns(from databaseURL: URL, tableName: String) -> [String] {
        let query = "PRAGMA table_info('\(tableName)');"
        guard let output = runSQLite(databaseURL: databaseURL, query: query) else {
            return []
        }

        return output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let fields = line.split(separator: "|", omittingEmptySubsequences: false)
                guard fields.count >= 2 else { return nil }
                return String(fields[1])
            }
    }

    private static func loadRows(
        from databaseURL: URL,
        tableName: String,
        columns: [String]
    ) -> [[(column: String, value: String)]]? {
        guard !columns.isEmpty else { return nil }

        let sqlColumns = columns.map(quotedIdentifier).joined(separator: ", ")
        let query = "SELECT \(sqlColumns) FROM \(quotedIdentifier(tableName));"
        guard let output = runSQLite(databaseURL: databaseURL, query: query, separator: "\t") else {
            return nil
        }

        let rows: [[(column: String, value: String)]] = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                var values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                if values.count < columns.count {
                    values.append(contentsOf: Array(repeating: "", count: columns.count - values.count))
                }
                return zip(columns, values).map { (column: $0.0, value: $0.1) }
            }
        return rows
    }

    private static func runSQLite(databaseURL: URL, query: String, separator: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")

        var arguments = ["-readonly", "-noheader"]
        if let separator {
            arguments.append(contentsOf: ["-separator", separator])
        }
        arguments.append(databaseURL.path)
        arguments.append(query)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDeletionColumnName(_ columnName: String) -> Bool {
        let normalized = columnName.uppercased()
        return normalized.contains("DELETE")
            || normalized.contains("TRASH")
            || normalized.contains("REMOV")
            || normalized.contains("INTRASH")
    }

    private static func isPotentialRecordingReferenceColumn(_ columnName: String) -> Bool {
        let normalized = columnName.uppercased()
        return normalized.contains("PATH")
            || normalized.contains("URL")
            || normalized.contains("FILE")
            || normalized.contains("NAME")
            || normalized.contains("UUID")
            || normalized.contains("IDENTIFIER")
            || normalized.contains("RECORDING")
    }

    private static func isPotentialTitleColumn(_ columnName: String) -> Bool {
        let normalized = columnName.uppercased()
        return normalized.contains("TITLE")
            || normalized.contains("NAME")
            || normalized.contains("LABEL")
            || normalized.contains("DISPLAY")
    }

    private static func isTruthy(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }

        if let intValue = Int(trimmed) {
            return intValue != 0
        }

        if let doubleValue = Double(trimmed) {
            return doubleValue != 0
        }

        if ["false", "no", "n", "f"].contains(trimmed) {
            return false
        }

        return !trimmed.isEmpty
    }

    private static func cleanTitle(_ value: String) -> String? {
        let cleaned = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.count > 240 { return nil }
        return cleaned
    }

    private static func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func orderedUniqueURLs(_ values: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return values.filter { seenPaths.insert($0.path).inserted }
    }

    fileprivate static let recordingNameRegex: NSRegularExpression = {
        let pattern = #"\d{8}\s\d{6}-[A-Za-z0-9_-]+(?:\.m4a)?"#
        return (try? NSRegularExpression(pattern: pattern)) ?? NSRegularExpression()
    }()
}

private struct RecordingBaseNameMatcher {
    private let availableBaseNames: Set<String>
    private let exactBaseNameLookup: [String: String]
    private let identifierLookup: [String: Set<String>]
    private let normalizedLookup: [String: Set<String>]

    init(availableBaseNames: Set<String>) {
        self.availableBaseNames = availableBaseNames

        var exactLookup: [String: String] = [:]
        var identifierLookup: [String: Set<String>] = [:]
        var normalizedLookup: [String: Set<String>] = [:]

        for baseName in availableBaseNames {
            exactLookup[baseName.lowercased()] = baseName

            let normalized = Self.normalizedIdentifier(baseName)
            if !normalized.isEmpty {
                normalizedLookup[normalized, default: []].insert(baseName)
            }

            for token in Self.identifierTokens(for: baseName) {
                identifierLookup[token, default: []].insert(baseName)
            }
        }

        self.exactBaseNameLookup = exactLookup
        self.identifierLookup = identifierLookup
        self.normalizedLookup = normalizedLookup
    }

    func extractMatchingBaseNames(from value: String) -> Set<String> {
        let cleanedValue = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedValue.isEmpty else { return [] }

        var matches = Set<String>()
        let lowercasedValue = cleanedValue.lowercased()

        for token in extractionCandidates(from: cleanedValue) {
            let lowercasedToken = token.lowercased()
            if let exactMatch = exactBaseNameLookup[lowercasedToken] {
                matches.insert(exactMatch)
            }

            if let identifierMatches = identifierLookup[lowercasedToken] {
                matches.formUnion(identifierMatches)
            }

            let normalized = Self.normalizedIdentifier(token)
            if let normalizedMatches = normalizedLookup[normalized] {
                matches.formUnion(normalizedMatches)
            }
        }

        if matches.isEmpty {
            for baseName in availableBaseNames where lowercasedValue.contains(baseName.lowercased()) {
                matches.insert(baseName)
            }
        }

        return matches
    }

    func looksLikeRecordingIdentifier(_ value: String) -> Bool {
        !extractMatchingBaseNames(from: value).isEmpty
    }

    private func extractionCandidates(from value: String) -> Set<String> {
        var candidates = Set<String>()

        func appendCandidate(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            candidates.insert(trimmed)
            if trimmed.lowercased().hasSuffix(".m4a") {
                candidates.insert(String(trimmed.dropLast(4)))
            }
        }

        appendCandidate(value)

        let fileComponent = URL(fileURLWithPath: value).lastPathComponent
        appendCandidate(fileComponent)

        let fullRange = NSRange(location: 0, length: (value as NSString).length)
        for match in VoiceMemosActiveRecordingFilter.recordingNameRegex.matches(in: value, options: [], range: fullRange) {
            guard let range = Range(match.range, in: value) else { continue }
            appendCandidate(String(value[range]))
        }

        for match in Self.identifierTokenRegex.matches(in: value, options: [], range: fullRange) {
            guard let range = Range(match.range, in: value) else { continue }
            appendCandidate(String(value[range]))
        }

        return candidates
    }

    private static func identifierTokens(for baseName: String) -> Set<String> {
        var tokens = Set<String>()
        let lowercasedBase = baseName.lowercased()
        tokens.insert(lowercasedBase)

        if let hyphenIndex = lowercasedBase.firstIndex(of: "-") {
            let suffix = String(lowercasedBase[lowercasedBase.index(after: hyphenIndex)...])
            if !suffix.isEmpty {
                tokens.insert(suffix)
            }
        }

        let nsBaseName = lowercasedBase as NSString
        let fullRange = NSRange(location: 0, length: nsBaseName.length)
        for match in identifierTokenRegex.matches(in: lowercasedBase, options: [], range: fullRange) {
            guard let range = Range(match.range, in: lowercasedBase) else { continue }
            let token = String(lowercasedBase[range])
            guard !token.allSatisfy(\.isNumber) else { continue }
            tokens.insert(token)
        }

        let normalized = normalizedIdentifier(lowercasedBase)
        if !normalized.isEmpty {
            tokens.insert(normalized)
        }

        return tokens
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static let identifierTokenRegex: NSRegularExpression = {
        let pattern = #"[A-Za-z0-9_-]{6,}"#
        return (try? NSRegularExpression(pattern: pattern)) ?? NSRegularExpression()
    }()
}

private enum VoiceMemoFileTitleExtractor {
    static func extractTitle(from fileURL: URL) -> String? {
#if os(macOS)
        let fallbackBaseName = fileURL.deletingPathExtension().lastPathComponent

        let asset = AVURLAsset(url: fileURL)
        let metadata = asset.commonMetadata
            + asset.metadata(forFormat: .quickTimeMetadata)
            + asset.metadata(forFormat: .iTunesMetadata)

        for item in metadata {
            if isTitleItem(item), let cleaned = cleanedTitle(item.stringValue, fallbackBaseName: fallbackBaseName) {
                return cleaned
            }
        }

        if let spotlightTitle = spotlightDisplayName(for: fileURL),
           let cleaned = cleanedTitle(spotlightTitle, fallbackBaseName: fallbackBaseName)
        {
            return cleaned
        }

        return nil
#else
        return nil
#endif
    }

#if os(macOS)
    private static func isTitleItem(_ item: AVMetadataItem) -> Bool {
        if let commonKey = item.commonKey?.rawValue.lowercased(), commonKey == "title" {
            return true
        }

        if let keyString = item.key as? String, keyString.lowercased().contains("title") {
            return true
        }

        if let identifier = item.identifier?.rawValue.lowercased(), identifier.contains("title") {
            return true
        }

        return false
    }
#endif

    private static func spotlightDisplayName(for fileURL: URL) -> String? {
        guard let item = MDItemCreate(nil, fileURL.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemDisplayName as CFString) as? String
    }

    private static func cleanedTitle(_ value: String?, fallbackBaseName: String) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let cleanedWithoutExtension = cleaned.lowercased().hasSuffix(".m4a")
            ? String(cleaned.dropLast(4))
            : cleaned
        if cleanedWithoutExtension.caseInsensitiveCompare(fallbackBaseName) == .orderedSame {
            return nil
        }
        return cleaned
    }
}
