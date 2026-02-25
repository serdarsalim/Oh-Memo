import Foundation

public enum TranscriptExtractionError: Error, Sendable, LocalizedError {
    case extractorNotFound
    case missingTranscript
    case processFailed(String)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .extractorNotFound:
            return "Extractor script was not found."
        case .missingTranscript:
            return "Transcript is missing for this recording."
        case .processFailed(let output):
            return output.isEmpty ? "Extractor process failed." : output
        case .invalidData(let message):
            return message
        }
    }
}

public protocol RecordingScanner: Sendable {
    func listRecordings(in folderURL: URL) async throws -> [RecordingFile]
}

public protocol TranscriptExtractor: Sendable {
    func extractTranscript(from fileURL: URL) async throws -> TranscriptData
}

public protocol FolderBookmarkStore: Sendable {
    func save(folderURL: URL) throws
    func resolveSavedFolderURL() throws -> URL?
    func clear() throws
}
