import Data
import Domain
import Foundation
import Platform
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
#if os(macOS)
import AppKit
import Darwin
#endif

struct CachedAITranscriptReport: Codable, Equatable, Sendable {
    let report: AITranscriptReport
    let transcriptDigest: String
    let analyzedAt: Date
}

@MainActor
final class AppModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var searchQuery: String = "" {
        didSet { refreshVisibleRecordings() }
    }
    @Published var sortOption: RecordingSortOption = .newestFirst {
        didSet { refreshVisibleRecordings() }
    }
    @Published var selectedRecordingID: String?
    @Published var allRecordings: [RecordingItem] = []
    @Published var visibleRecordings: [RecordingItem] = []
    @Published private(set) var descriptionsByRecordingID: [String: String]
    @Published var scanSummary: ScanResult?
    @Published var isScanning = false
    @Published var progressText = ""
    @Published var progressFraction: Double?
    @Published var transientMessage: String?
    @Published var failures: [ScanFailure] = []
    @Published var isShowingFailures = false
    @Published var errorBanner: String?
    @Published var appearanceMode: AppearanceMode {
        didSet { saveAppearanceMode() }
    }
    @Published var isShowingAISettings = false
    @Published var isShowingAIPromptEditor = false
    @Published private(set) var aiIsAnalyzing = false
    @Published private(set) var aiAnalysisError: String?
    @Published private(set) var aiReportsByRecordingID: [String: CachedAITranscriptReport] = [:]
    @Published private(set) var hasOpenAIAPIKey = false
    @Published private(set) var openAIAPIKeyMask = ""
    @Published private(set) var aiAnalysisPrompt: String

    private let scanUseCase: ScanRecordingsUseCase
    private let searchUseCase: SearchTranscriptsUseCase
    private let exportUseCase: ExportTranscriptsUseCase
    private let bookmarkStore: FolderBookmarkStore
    private let folderPicker: FolderPickerClient
    private let clipboard: ClipboardClient
    private let saveClient: FileSaveClient
    private let transcriptAnalyzer: OpenAITranscriptAnalyzer
    private let defaults: UserDefaults

    private var securityScopedURL: URL?
    private var transientMessageTask: Task<Void, Never>?
    private var autoRescanDebounceTask: Task<Void, Never>?
    private var pendingAutoRescan = false
#if os(macOS)
    private var folderWatchSource: DispatchSourceFileSystemObject?
    private var folderWatchFileDescriptor: CInt = -1
#endif
    private static let appearanceModeKey = "voiceMemo.appearanceMode"
    private static let descriptionsKey = "voiceMemo.recordingDescriptions.v1"
    private static let aiReportsKey = "voiceMemo.aiReports.v1"
    private static let openAIAPIKeyStorageKey = "voiceMemo.openAIApiKey.v1"
    private static let aiAnalysisPromptKey = "voiceMemo.aiAnalysisPrompt.v1"

    init(
        scanUseCase: ScanRecordingsUseCase,
        searchUseCase: SearchTranscriptsUseCase,
        exportUseCase: ExportTranscriptsUseCase,
        bookmarkStore: FolderBookmarkStore,
        folderPicker: FolderPickerClient,
        clipboard: ClipboardClient,
        saveClient: FileSaveClient,
        transcriptAnalyzer: OpenAITranscriptAnalyzer = OpenAITranscriptAnalyzer(),
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.appearanceMode = Self.loadAppearanceMode(defaults: defaults)
        self.descriptionsByRecordingID = Self.loadRecordingDescriptions(defaults: defaults)
        self.aiReportsByRecordingID = Self.loadAIReports(defaults: defaults)
        self.aiAnalysisPrompt = Self.loadAIAnalysisPrompt(defaults: defaults)
        self.scanUseCase = scanUseCase
        self.searchUseCase = searchUseCase
        self.exportUseCase = exportUseCase
        self.bookmarkStore = bookmarkStore
        self.folderPicker = folderPicker
        self.clipboard = clipboard
        self.saveClient = saveClient
        self.transcriptAnalyzer = transcriptAnalyzer
        refreshOpenAIAPIKeyState()
    }

    deinit {
        autoRescanDebounceTask?.cancel()
        transientMessageTask?.cancel()
#if os(macOS)
        if let source = folderWatchSource {
            folderWatchSource = nil
            source.cancel()
        } else if folderWatchFileDescriptor >= 0 {
            close(folderWatchFileDescriptor)
            folderWatchFileDescriptor = -1
        }
#endif
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    var selectedRecording: RecordingItem? {
        guard let selectedRecordingID else {
            return nil
        }

        return allRecordings.first(where: { $0.id == selectedRecordingID })
    }

    var folderPathDescription: String {
        folderURL?.path ?? "No folder selected"
    }

    var folderName: String {
        folderURL?.lastPathComponent ?? "No Folder"
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }

    var defaultAIAnalysisPrompt: String {
        OpenAITranscriptAnalyzer.defaultSystemPrompt
    }

    func onAppear() {
        restoreSavedFolderIfAvailable()
    }

    func chooseFolder() {
        let pickedFolder = folderPicker.pickFolder(initialURL: folderURL)
        guard let pickedFolder else {
            return
        }

        do {
            try bookmarkStore.save(folderURL: pickedFolder)
            setFolder(pickedFolder)
            scanFolder()
        } catch {
            errorBanner = "Could not save folder permission: \(error.localizedDescription)"
        }
    }

    func rescan() {
        scanFolder()
    }

    func openCurrentFolderInFinder() {
        guard let folderURL else {
            showTransientMessage("No folder selected.")
            return
        }
#if os(macOS)
        NSWorkspace.shared.open(folderURL)
#endif
    }

    func copyCurrentTranscript() {
        guard let selected = selectedRecording, let text = selected.transcript?.text, !text.isEmpty else {
            showTransientMessage("No transcript selected to copy.")
            return
        }

        clipboard.setString(text)
        showTransientMessage("Copied current transcript")
    }

    func copyAllTranscripts() {
        let merged = exportUseCase.mergedText(for: allRecordings)
        guard !merged.isEmpty else {
            showTransientMessage("No transcript content to copy")
            return
        }

        clipboard.setString(merged)
        showTransientMessage("Copied all transcripts")
    }

    func exportText() {
        let merged = exportUseCase.mergedText(for: allRecordings)
        guard let data = merged.data(using: .utf8), !data.isEmpty else {
            showTransientMessage("No transcript content to export")
            return
        }

        do {
            _ = try saveClient.save(
                data: data,
                suggestedFileName: "voice-memo-transcripts.txt",
                contentType: .plainText
            )
            showTransientMessage("Exported TXT")
        } catch {
            errorBanner = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportJSON() {
        do {
            let data = try exportUseCase.mergedJSON(for: allRecordings)
            guard !data.isEmpty else {
                showTransientMessage("No transcript content to export")
                return
            }

            _ = try saveClient.save(
                data: data,
                suggestedFileName: "voice-memo-transcripts.json",
                contentType: .json
            )
            showTransientMessage("Exported JSON")
        } catch {
            errorBanner = "Export failed: \(error.localizedDescription)"
        }
    }

    func showFailures() {
        guard !failures.isEmpty else {
            return
        }
        isShowingFailures = true
    }

    func dismissMessage() {
        transientMessageTask?.cancel()
        transientMessageTask = nil
        transientMessage = nil
    }

    func dismissError() {
        errorBanner = nil
    }

    func description(for recordingID: String) -> String {
        descriptionsByRecordingID[recordingID] ?? ""
    }

    var selectedAIReport: CachedAITranscriptReport? {
        guard let recordingID = selectedRecordingID else { return nil }
        return aiReportsByRecordingID[recordingID]
    }

    func setDescription(_ description: String, for recordingID: String) {
        let isEmpty = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let previous = descriptionsByRecordingID[recordingID] ?? ""
        let nextValue = isEmpty ? "" : description

        guard previous != nextValue else { return }

        if isEmpty {
            descriptionsByRecordingID.removeValue(forKey: recordingID)
        } else {
            descriptionsByRecordingID[recordingID] = description
        }
        saveRecordingDescriptions()
    }

    func saveOpenAIAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.openAIAPIKeyStorageKey)
            refreshOpenAIAPIKeyState()
            showTransientMessage("Removed OpenAI API key")
            return
        }

        defaults.set(trimmed, forKey: Self.openAIAPIKeyStorageKey)
        refreshOpenAIAPIKeyState()
        showTransientMessage("Saved OpenAI API key")
    }

    func saveAIAnalysisPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resetAIAnalysisPromptToDefault()
            return
        }

        aiAnalysisPrompt = prompt
        defaults.set(prompt, forKey: Self.aiAnalysisPromptKey)
        showTransientMessage("Saved AI prompt")
    }

    func resetAIAnalysisPromptToDefault() {
        aiAnalysisPrompt = OpenAITranscriptAnalyzer.defaultSystemPrompt
        defaults.removeObject(forKey: Self.aiAnalysisPromptKey)
        showTransientMessage("Reset AI prompt to default")
    }

    func analyzeSelectedTranscript(force: Bool = false) {
        guard let recording = selectedRecording else {
            aiAnalysisError = "Select a transcript first."
            return
        }
        guard let transcript = recording.transcript?.text, !transcript.isEmpty else {
            aiAnalysisError = "Selected recording has no transcript text."
            return
        }
        guard let apiKey = defaults.string(forKey: Self.openAIAPIKeyStorageKey), !apiKey.isEmpty else {
            aiAnalysisError = AIAnalysisError.missingAPIKey.localizedDescription
            isShowingAISettings = true
            return
        }

        let digest = digestForTranscript(transcript)
        if !force,
           let cached = aiReportsByRecordingID[recording.id],
           cached.transcriptDigest == digest
        {
            aiAnalysisError = nil
            return
        }

        aiIsAnalyzing = true
        aiAnalysisError = nil
        let promptForAnalysis = aiAnalysisPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? OpenAITranscriptAnalyzer.defaultSystemPrompt
            : aiAnalysisPrompt

        Task {
            do {
                let report = try await transcriptAnalyzer.analyze(
                    transcript: transcript,
                    apiKey: apiKey,
                    systemPrompt: promptForAnalysis
                )
                let cached = CachedAITranscriptReport(
                    report: report,
                    transcriptDigest: digest,
                    analyzedAt: Date()
                )
                aiReportsByRecordingID[recording.id] = cached
                saveAIReports()
            } catch {
                aiAnalysisError = error.localizedDescription
            }

            aiIsAnalyzing = false
        }
    }

    func analyzeSelectedTranscriptIfMissing() {
        guard let recording = selectedRecording else { return }
        guard aiReportsByRecordingID[recording.id] == nil else { return }
        analyzeSelectedTranscript(force: false)
    }

    func copySelectedAIReport() {
        guard let report = selectedAIReport?.report else {
            showTransientMessage("No AI report to copy")
            return
        }

        clipboard.setString(format(report: report))
        showTransientMessage("Copied AI report")
    }

    private func restoreSavedFolderIfAvailable() {
        do {
            if let savedURL = try bookmarkStore.resolveSavedFolderURL() {
                setFolder(savedURL)
                scanFolder()
            }
        } catch {
            errorBanner = "Could not restore saved folder. Choose a folder again."
        }
    }

    private func setFolder(_ folder: URL) {
        stopWatchingFolder()

        if let current = securityScopedURL {
            current.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }

        _ = folder.startAccessingSecurityScopedResource()
        securityScopedURL = folder
        folderURL = folder
        startWatchingFolder(folder)
    }

    private func scanFolder() {
        guard let folderURL else {
            return
        }

        if isScanning {
            pendingAutoRescan = true
            return
        }

        isScanning = true
        pendingAutoRescan = false
        progressText = "Scanning..."
        progressFraction = nil
        failures = []

        let useCase = scanUseCase
        let folderToScan = folderURL

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await useCase.execute(folderURL: folderToScan)
                }.value

                allRecordings = result.recordings
                scanSummary = result
                failures = result.failures
                refreshVisibleRecordings()

                if selectedRecordingID == nil {
                    selectedRecordingID = visibleRecordings.first?.id
                }

                progressText = "Scan complete"
                progressFraction = 1
            } catch {
                errorBanner = "Scan failed: \(error.localizedDescription)"
                progressText = "Scan failed"
                progressFraction = nil
            }

            isScanning = false

            if pendingAutoRescan {
                pendingAutoRescan = false
                scanFolder()
            }
        }
    }

    private func refreshVisibleRecordings() {
        visibleRecordings = searchUseCase.execute(
            recordings: allRecordings,
            query: searchQuery,
            sort: sortOption
        )

        if let selectedRecordingID,
           !visibleRecordings.contains(where: { $0.id == selectedRecordingID }) {
            self.selectedRecordingID = visibleRecordings.first?.id
        }
    }

    private func showTransientMessage(_ message: String, autoDismissDelayNanoseconds: UInt64 = 1_000_000_000) {
        transientMessageTask?.cancel()
        transientMessage = message

        transientMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: autoDismissDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.transientMessage == message else { return }

            self.transientMessage = nil
            self.transientMessageTask = nil
        }
    }

    private func scheduleAutoRescan() {
        autoRescanDebounceTask?.cancel()
        autoRescanDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.runAutoRescanIfNeeded()
        }
    }

    private func runAutoRescanIfNeeded() async {
        guard folderURL != nil else { return }
        if isScanning {
            pendingAutoRescan = true
            return
        }
        scanFolder()
    }

    private func startWatchingFolder(_ folder: URL) {
#if os(macOS)
        let fileDescriptor = open(folder.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .link, .revoke],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleAutoRescan()
        }
        source.setCancelHandler { [weak self] in
            close(fileDescriptor)
            self?.folderWatchFileDescriptor = -1
        }

        folderWatchSource = source
        folderWatchFileDescriptor = fileDescriptor
        source.resume()
#endif
    }

    private func stopWatchingFolder() {
#if os(macOS)
        autoRescanDebounceTask?.cancel()
        autoRescanDebounceTask = nil

        if let source = folderWatchSource {
            folderWatchSource = nil
            source.cancel()
        } else if folderWatchFileDescriptor >= 0 {
            close(folderWatchFileDescriptor)
            folderWatchFileDescriptor = -1
        }
#endif
    }

    private func saveAppearanceMode() {
        defaults.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey)
    }

    private func saveRecordingDescriptions() {
        defaults.set(descriptionsByRecordingID, forKey: Self.descriptionsKey)
    }

    private func saveAIReports() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(aiReportsByRecordingID) else { return }
        defaults.set(data, forKey: Self.aiReportsKey)
    }

    private func refreshOpenAIAPIKeyState() {
        guard let key = defaults.string(forKey: Self.openAIAPIKeyStorageKey), !key.isEmpty else {
            hasOpenAIAPIKey = false
            openAIAPIKeyMask = "Not set"
            return
        }

        hasOpenAIAPIKey = true
        let suffix = String(key.suffix(4))
        openAIAPIKeyMask = "••••\(suffix)"
    }

    private func digestForTranscript(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func format(report: AITranscriptReport) -> String {
        let actionItems = report.actionItems.map { "• \($0)" }.joined(separator: "\n")
        let strengths = report.strengths.map { "• \($0)" }.joined(separator: "\n")
        let improvements = report.improvements.map { "• \($0)" }.joined(separator: "\n")

        return """
        Summary
        \(report.summary)

        Conversion sentiment: \(report.score)/10 (\(report.sentiment))

        Action Items
        \(actionItems)

        What went well
        \(strengths)

        What to improve
        \(improvements)
        """
    }

    private static func loadAppearanceMode(defaults: UserDefaults) -> AppearanceMode {
        guard
            let rawValue = defaults.string(forKey: Self.appearanceModeKey),
            let mode = AppearanceMode(rawValue: rawValue)
        else {
            return .system
        }
        return mode
    }

    private static func loadRecordingDescriptions(defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: Self.descriptionsKey) as? [String: String] ?? [:]
    }

    private static func loadAIReports(defaults: UserDefaults) -> [String: CachedAITranscriptReport] {
        guard let data = defaults.data(forKey: Self.aiReportsKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: CachedAITranscriptReport].self, from: data)) ?? [:]
    }

    private static func loadAIAnalysisPrompt(defaults: UserDefaults) -> String {
        let prompt = defaults.string(forKey: Self.aiAnalysisPromptKey) ?? OpenAITranscriptAnalyzer.defaultSystemPrompt
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? OpenAITranscriptAnalyzer.defaultSystemPrompt
            : prompt
    }
}
