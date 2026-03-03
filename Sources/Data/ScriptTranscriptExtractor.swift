import Domain
import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct ScriptTranscriptExtractor: TranscriptExtractor, Sendable {
    private let extractorURL: URL?
    private let environment: [String: String]

    public init(extractorURL: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.extractorURL = extractorURL ?? ScriptTranscriptExtractor.resolveDefaultExtractorURL(environment: environment)
        self.environment = environment
    }

    public func extractTranscript(from fileURL: URL) async throws -> TranscriptData {
        if let extractorURL {
            do {
                let jsonResult = try await runExtractor(scriptURL: extractorURL, arguments: ["--json", fileURL.path])
                guard jsonResult.exitCode == 0 else {
                    let message = [jsonResult.standardError, jsonResult.standardOutput]
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw TranscriptExtractionError.processFailed(message)
                }

                let jsonText = jsonResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !jsonText.isEmpty else {
                    throw TranscriptExtractionError.missingTranscript
                }

                let text = try ScriptTranscriptExtractor.extractPlainText(fromJSONText: jsonText)
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else {
                    throw TranscriptExtractionError.missingTranscript
                }

                let locale = ScriptTranscriptExtractor.extractLocale(fromJSONText: jsonText)
                return TranscriptData(text: cleaned, jsonPayload: jsonText, localeIdentifier: locale)
            } catch {
                // Fall through to native extractor when script execution is unavailable.
            }
        }

        let jsonText = try ScriptTranscriptExtractor.extractTranscriptJSONFromM4A(fileURL: fileURL)
        let text = try ScriptTranscriptExtractor.extractPlainText(fromJSONText: jsonText)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw TranscriptExtractionError.missingTranscript
        }

        let locale = ScriptTranscriptExtractor.extractLocale(fromJSONText: jsonText)

        return TranscriptData(text: cleaned, jsonPayload: jsonText, localeIdentifier: locale)
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 20
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        var mergedEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { mergedEnvironment[$0.key] = $0.value }
        process.environment = mergedEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutTask = Task.detached(priority: .utility) {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached(priority: .utility) {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let finishedInTime = await waitForProcessExit(process, timeout: timeout)
        if !finishedInTime {
            process.terminate()
            var stopped = await waitForProcessExit(process, timeout: 2)
            if !stopped {
                forceKill(process)
                stopped = await waitForProcessExit(process, timeout: 1)
            }
            if !stopped {
                stdoutPipe.fileHandleForReading.closeFile()
                stderrPipe.fileHandleForReading.closeFile()
                stdoutTask.cancel()
                stderrTask.cancel()
                throw TranscriptExtractionError.processFailed("Extractor timed out while reading transcript.")
            }
            _ = await stdoutTask.value
            _ = await stderrTask.value
            throw TranscriptExtractionError.processFailed("Extractor timed out while reading transcript.")
        }

        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value

        let standardOutput = String(data: stdoutData, encoding: .utf8) ?? ""
        let standardError = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessResult(
            exitCode: Int(process.terminationStatus),
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    private func runExtractor(scriptURL: URL, arguments: [String]) async throws -> ProcessResult {
        if FileManager.default.isExecutableFile(atPath: scriptURL.path) {
            return try await runProcess(executableURL: scriptURL, arguments: arguments)
        }

        let envExecutable = URL(fileURLWithPath: "/usr/bin/env")
        return try await runProcess(executableURL: envExecutable, arguments: ["python3", scriptURL.path] + arguments)
    }

    private struct ProcessResult {
        let exitCode: Int
        let standardOutput: String
        let standardError: String
    }

    private func waitForProcessExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let safeTimeout = max(timeout, 0)
        let deadline = Date().addingTimeInterval(safeTimeout)

        while process.isRunning {
            if Date() >= deadline {
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return true
    }

    private func forceKill(_ process: Process) {
#if canImport(Darwin)
        if process.processIdentifier > 0 {
            kill(process.processIdentifier, SIGKILL)
        }
#endif
    }
}

private extension ScriptTranscriptExtractor {
    static func resolveDefaultExtractorURL(environment: [String: String]) -> URL? {
        if let path = environment["VOICE_MEMO_EXTRACTOR_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let rootCandidate = currentDirectory.appendingPathComponent("extract-apple-voice-memos-transcript")
        if fileManager.fileExists(atPath: rootCandidate.path) {
            return rootCandidate
        }

        let bundleCandidate = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("extract-apple-voice-memos-transcript")
        if fileManager.fileExists(atPath: bundleCandidate.path) {
            return bundleCandidate
        }

        if let bundledPath = Bundle.main.path(forResource: "extract-apple-voice-memos-transcript", ofType: nil) {
            return URL(fileURLWithPath: bundledPath)
        }

        return nil
    }

    static func extractPlainText(fromJSONText jsonText: String) throws -> String {
        guard let data = jsonText.data(using: .utf8) else {
            throw TranscriptExtractionError.invalidData("Transcript data is not valid UTF-8.")
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let root = jsonObject as? [String: Any] else {
            throw TranscriptExtractionError.invalidData("Transcript JSON root is invalid.")
        }

        guard let attributedString = root["attributedString"] else {
            throw TranscriptExtractionError.invalidData("Transcript payload does not include attributedString.")
        }

        if let interleaved = attributedString as? [Any] {
            return interleaved.compactMap { $0 as? String }.joined()
        }

        if let dictionary = attributedString as? [String: Any],
           let runs = dictionary["runs"] as? [Any] {
            return runs.compactMap { $0 as? String }.joined()
        }

        throw TranscriptExtractionError.invalidData("Unsupported transcript payload format.")
    }

    static func extractTranscriptJSONFromM4A(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)

        guard let moov = try findAtom(handle: handle, endOffset: fileSize, targetType: "moov") else {
            throw TranscriptExtractionError.missingTranscript
        }
        guard let trak = try findAtom(handle: handle, endOffset: moov.endOffset, targetType: "trak") else {
            throw TranscriptExtractionError.missingTranscript
        }
        guard let udta = try findAtom(handle: handle, endOffset: trak.endOffset, targetType: "udta") else {
            throw TranscriptExtractionError.missingTranscript
        }
        guard let tsrp = try findAtom(handle: handle, endOffset: udta.endOffset, targetType: "tsrp") else {
            throw TranscriptExtractionError.missingTranscript
        }

        let payloadSize = Int(tsrp.endOffset - tsrp.payloadOffset)
        guard payloadSize > 0 else {
            throw TranscriptExtractionError.missingTranscript
        }

        try handle.seek(toOffset: tsrp.payloadOffset)
        let data = try handle.read(upToCount: payloadSize) ?? Data()
        guard !data.isEmpty else {
            throw TranscriptExtractionError.missingTranscript
        }

        guard let jsonText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !jsonText.isEmpty
        else {
            throw TranscriptExtractionError.invalidData("Transcript data is not valid UTF-8.")
        }
        return jsonText
    }

    private struct AtomMatch {
        let payloadOffset: UInt64
        let endOffset: UInt64
    }

    private static func findAtom(
        handle: FileHandle,
        endOffset: UInt64,
        targetType: String
    ) throws -> AtomMatch? {
        while try handle.offset() < endOffset {
            let atomStart = try handle.offset()
            guard let header = try readAtomHeader(handle: handle), header.size > 0 else {
                break
            }

            let atomEnd = atomStart + header.size
            if atomEnd > endOffset {
                break
            }

            if header.type == targetType {
                return AtomMatch(payloadOffset: try handle.offset(), endOffset: atomEnd)
            }

            try handle.seek(toOffset: atomEnd)
        }
        return nil
    }

    private struct AtomHeader {
        let type: String
        let size: UInt64
    }

    private static func readAtomHeader(handle: FileHandle) throws -> AtomHeader? {
        let baseHeader = try handle.read(upToCount: 8) ?? Data()
        guard baseHeader.count == 8 else {
            return nil
        }

        let rawSize = baseHeader.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let typeData = baseHeader.dropFirst(4).prefix(4)
        let type = String(data: typeData, encoding: .ascii) ?? ""

        if rawSize == 1 {
            let extended = try handle.read(upToCount: 8) ?? Data()
            guard extended.count == 8 else {
                return nil
            }
            let size = extended.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            return AtomHeader(type: type, size: size)
        }

        return AtomHeader(type: type, size: UInt64(rawSize))
    }

    static func extractLocale(fromJSONText jsonText: String) -> String? {
        guard
            let data = jsonText.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let root = jsonObject as? [String: Any],
            let locale = root["locale"] as? [String: Any],
            let identifier = locale["identifier"] as? String
        else {
            return nil
        }

        return identifier
    }
}
