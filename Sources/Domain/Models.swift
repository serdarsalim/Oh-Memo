import Foundation

public enum TranscriptStatus: String, Codable, Sendable {
    case ready
    case missing
    case failed
}

public enum RecordingSortOption: String, CaseIterable, Identifiable, Sendable {
    case newestFirst = "Newest"
    case oldestFirst = "Oldest"
    case longestTranscript = "Longest"
    case recentlyScanned = "Recently Scanned"

    public var id: String { rawValue }
}

public struct RecordingFile: Identifiable, Hashable, Sendable {
    public let fileURL: URL
    public let fileName: String
    public let recordedAt: Date?
    public let fileModifiedAt: Date

    public var id: String { fileURL.path }

    public init(fileURL: URL, fileName: String, recordedAt: Date?, fileModifiedAt: Date) {
        self.fileURL = fileURL
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.fileModifiedAt = fileModifiedAt
    }

    public var effectiveDate: Date {
        recordedAt ?? fileModifiedAt
    }
}

public struct TranscriptData: Hashable, Sendable {
    public let text: String
    public let jsonPayload: String?
    public let localeIdentifier: String?

    public init(text: String, jsonPayload: String?, localeIdentifier: String?) {
        self.text = text
        self.jsonPayload = jsonPayload
        self.localeIdentifier = localeIdentifier
    }
}

public struct RecordingItem: Identifiable, Hashable, Sendable {
    public let source: RecordingFile
    public let transcript: TranscriptData?
    public let status: TranscriptStatus
    public let scanIndex: Int
    public let errorMessage: String?

    public var id: String { source.id }

    public init(
        source: RecordingFile,
        transcript: TranscriptData?,
        status: TranscriptStatus,
        scanIndex: Int,
        errorMessage: String?
    ) {
        self.source = source
        self.transcript = transcript
        self.status = status
        self.scanIndex = scanIndex
        self.errorMessage = errorMessage
    }

    public var searchText: String {
        transcript?.text.lowercased() ?? ""
    }

    public var snippet: String {
        let text = transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return status == .failed ? "Failed to extract transcript" : "No transcript"
        }

        let maxLength = 110
        if text.count <= maxLength {
            return text
        }

        let index = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<index]) + "..."
    }
}

public struct ScanProgress: Sendable {
    public let processed: Int
    public let total: Int
    public let currentFileName: String

    public init(processed: Int, total: Int, currentFileName: String) {
        self.processed = processed
        self.total = total
        self.currentFileName = currentFileName
    }
}

public struct ScanFailure: Hashable, Sendable {
    public let fileName: String
    public let message: String

    public init(fileName: String, message: String) {
        self.fileName = fileName
        self.message = message
    }
}

public struct ScanResult: Sendable {
    public let recordings: [RecordingItem]
    public let failures: [ScanFailure]

    public init(recordings: [RecordingItem], failures: [ScanFailure]) {
        self.recordings = recordings
        self.failures = failures
    }

    public var readyCount: Int {
        recordings.count
    }

    public var missingCount: Int {
        0
    }

    public var failedCount: Int {
        failures.count
    }
}
