import Foundation

public struct ScanRecordingsUseCase: Sendable {
    private let scanner: RecordingScanner
    private let extractor: TranscriptExtractor

    public init(scanner: RecordingScanner, extractor: TranscriptExtractor) {
        self.scanner = scanner
        self.extractor = extractor
    }

    public func execute(folderURL: URL) async throws -> ScanResult {
        let files = try await scanner.listRecordings(in: folderURL)
        var recordings: [RecordingItem] = []
        var failures: [ScanFailure] = []

        for (index, file) in files.enumerated() {
            do {
                let transcript = try await extractor.extractTranscript(from: file.fileURL)
                recordings.append(
                    RecordingItem(
                        source: file,
                        transcript: transcript,
                        status: .ready,
                        scanIndex: index,
                        errorMessage: nil
                    )
                )
            } catch let extractionError as TranscriptExtractionError {
                switch extractionError {
                case .missingTranscript:
                    recordings.append(
                        RecordingItem(
                            source: file,
                            transcript: nil,
                            status: .missing,
                            scanIndex: index,
                            errorMessage: extractionError.localizedDescription
                        )
                    )
                default:
                    let message = extractionError.localizedDescription
                    recordings.append(
                        RecordingItem(
                            source: file,
                            transcript: nil,
                            status: .failed,
                            scanIndex: index,
                            errorMessage: message
                        )
                    )
                    failures.append(ScanFailure(fileName: file.fileName, message: message))
                }
            } catch {
                let message = error.localizedDescription
                recordings.append(
                    RecordingItem(
                        source: file,
                        transcript: nil,
                        status: .failed,
                        scanIndex: index,
                        errorMessage: message
                    )
                )
                failures.append(ScanFailure(fileName: file.fileName, message: message))
            }
        }

        return ScanResult(recordings: recordings, failures: failures)
    }
}

public struct SearchTranscriptsUseCase: Sendable {
    public init() {}

    public func execute(
        recordings: [RecordingItem],
        query: String,
        sort: RecordingSortOption
    ) -> [RecordingItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered: [RecordingItem]
        if normalizedQuery.isEmpty {
            filtered = recordings
        } else {
            filtered = recordings.filter { $0.searchText.contains(normalizedQuery) }
        }

        return sortRecordings(filtered, by: sort)
    }

    private func sortRecordings(_ recordings: [RecordingItem], by sort: RecordingSortOption) -> [RecordingItem] {
        switch sort {
        case .newestFirst:
            return recordings.sorted { lhs, rhs in
                let left = lhs.source.effectiveDate
                let right = rhs.source.effectiveDate
                if left == right {
                    return lhs.source.fileName > rhs.source.fileName
                }
                return left > right
            }
        case .oldestFirst:
            return recordings.sorted { lhs, rhs in
                let left = lhs.source.effectiveDate
                let right = rhs.source.effectiveDate
                if left == right {
                    return lhs.source.fileName < rhs.source.fileName
                }
                return left < right
            }
        case .longestTranscript:
            return recordings.sorted { lhs, rhs in
                let leftCount = lhs.transcript?.text.count ?? 0
                let rightCount = rhs.transcript?.text.count ?? 0
                if leftCount == rightCount {
                    return lhs.source.effectiveDate > rhs.source.effectiveDate
                }
                return leftCount > rightCount
            }
        case .recentlyScanned:
            return recordings.sorted { $0.scanIndex > $1.scanIndex }
        }
    }
}

public struct ExportTranscriptsUseCase: Sendable {
    public init() {}

    public func mergedText(for recordings: [RecordingItem]) -> String {
        var sections: [String] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for recording in recordings where recording.status == .ready {
            let title = recording.source.fileName
            let dateText = formatter.string(from: recording.source.effectiveDate)
            let body = recording.transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !body.isEmpty else { continue }
            sections.append("Recording: \(title)\nDate: \(dateText)\n\n\(body)")
        }

        return sections.joined(separator: "\n\n--------------------------------\n\n")
    }

    public func mergedJSON(for recordings: [RecordingItem]) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let payload: [[String: Any]] = recordings.compactMap { recording in
            guard recording.status == .ready, let transcript = recording.transcript else {
                return nil
            }

            var item: [String: Any] = [
                "recording": recording.source.fileName,
                "path": recording.source.fileURL.path,
                "effectiveDate": formatter.string(from: recording.source.effectiveDate),
                "status": recording.status.rawValue,
                "text": transcript.text
            ]

            if let rawPayload = transcript.jsonPayload {
                item["rawPayload"] = rawPayload
            }

            if let locale = transcript.localeIdentifier {
                item["locale"] = locale
            }

            return item
        }

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
