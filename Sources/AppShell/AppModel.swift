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
    @Published private(set) var editedTranscriptTextByRecordingID: [String: String]
    @Published private(set) var hasOpenAIAPIKey = false
    @Published private(set) var openAIAPIKeyMask = ""
    @Published private(set) var aiAnalysisPrompt: String
    @Published var showArchivedRecordings: Bool {
        didSet {
            saveShowArchivedRecordings()
            refreshVisibleRecordings()
        }
    }
    @Published var includeArchivedInBulkExport: Bool {
        didSet { saveIncludeArchivedInBulkExport() }
    }

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
    private static let editedTranscriptTextKey = "voiceMemo.editedTranscriptText.v1"
    private static let openAIAPIKeyStorageKey = "voiceMemo.openAIApiKey.v1"
    private static let aiAnalysisPromptKey = "voiceMemo.aiAnalysisPrompt.v1"
    private static let archivedRecordingIDsKey = "voiceMemo.archivedRecordingIDs.v1"
    private static let showArchivedRecordingsKey = "voiceMemo.showArchivedRecordings.v1"
    private static let includeArchivedInBulkExportKey = "voiceMemo.includeArchivedInBulkExport.v1"
    private static let initialScanBatchSize = 15
    private static var defaultRecordingsFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", isDirectory: true)
    }
    private var archivedRecordingIDs: Set<String>

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
        self.editedTranscriptTextByRecordingID = Self.loadEditedTranscriptText(defaults: defaults)
        self.aiAnalysisPrompt = Self.loadAIAnalysisPrompt(defaults: defaults)
        self.archivedRecordingIDs = Self.loadArchivedRecordingIDs(defaults: defaults)
        self.showArchivedRecordings = Self.loadShowArchivedRecordings(defaults: defaults)
        self.includeArchivedInBulkExport = Self.loadIncludeArchivedInBulkExport(defaults: defaults)
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

        guard let recording = allRecordings.first(where: { $0.id == selectedRecordingID }) else {
            return nil
        }
        return recordingWithEditedTranscript(recording)
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

    var defaultRecordingsFolderPath: String {
        Self.defaultRecordingsFolderURL.path
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

    func resetFolderToDefaultRecordings() {
        guard applyDefaultRecordingsFolder(showFeedback: true) else {
            errorBanner = "Default Voice Memos folder was not found at \(Self.defaultRecordingsFolderURL.path)."
            return
        }
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
        guard let selected = selectedRecording else {
            showTransientMessage("No transcript selected to copy.")
            return
        }

        guard let section = exportUseCase.sectionText(for: selected, titleProvider: displayTitleForExport) else {
            showTransientMessage("No transcript selected to copy.")
            return
        }

        clipboard.setString(section)
        showTransientMessage("Copied current transcript")
    }

    func copyAllTranscripts() {
        let merged = exportUseCase.mergedText(for: recordingsForBulkExport(), titleProvider: displayTitleForExport)
        guard !merged.isEmpty else {
            showTransientMessage("No transcript content to copy")
            return
        }

        clipboard.setString(merged)
        showTransientMessage("Copied all transcripts")
    }

    func exportText() {
        let merged = exportUseCase.mergedText(for: recordingsForBulkExport(), titleProvider: displayTitleForExport)
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
            let data = try exportUseCase.mergedJSON(for: recordingsForBulkExport())
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

    private func displayTitleForExport(_ recording: RecordingItem) -> String {
        let descriptionText = description(for: recording.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if !descriptionText.isEmpty {
            return descriptionText
        }

        let voiceMemoTitle = recording.source.voiceMemoTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !voiceMemoTitle.isEmpty {
            return voiceMemoTitle
        }

        return ""
    }

    private func recordingsForBulkExport() -> [RecordingItem] {
        if includeArchivedInBulkExport {
            return allRecordings.map(recordingWithEditedTranscript)
        }
        return allRecordings
            .filter { !archivedRecordingIDs.contains($0.id) }
            .map(recordingWithEditedTranscript)
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

    private func autoApplySuggestedRecordingTitleIfNeeded(_ suggestedTitle: String?, for recording: RecordingItem) {
        guard let suggestedTitle else { return }
        let trimmedSuggestion = suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSuggestion.isEmpty else { return }
        let existingDescription = description(for: recording.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard existingDescription != trimmedSuggestion else { return }
        setDescription(trimmedSuggestion, for: recording.id)
        showTransientMessage("Renamed recording from AI suggestion")
    }

    func setEditedTranscriptText(_ text: String, for recordingID: String) {
        guard let original = originalTranscriptText(for: recordingID) else { return }
        if text == original {
            if editedTranscriptTextByRecordingID.removeValue(forKey: recordingID) != nil {
                saveEditedTranscriptText()
                refreshVisibleRecordings()
            }
            return
        }

        if editedTranscriptTextByRecordingID[recordingID] != text {
            editedTranscriptTextByRecordingID[recordingID] = text
            saveEditedTranscriptText()
            refreshVisibleRecordings()
        }
    }

    func revertTranscriptToOriginal(for recordingID: String) {
        guard editedTranscriptTextByRecordingID.removeValue(forKey: recordingID) != nil else { return }
        saveEditedTranscriptText()
        refreshVisibleRecordings()
        showTransientMessage("Reverted to original")
    }

    func isTranscriptEdited(for recordingID: String) -> Bool {
        editedTranscriptTextByRecordingID[recordingID] != nil
    }

    func isArchived(recordingID: String) -> Bool {
        archivedRecordingIDs.contains(recordingID)
    }

    func archiveRecording(_ recordingID: String) {
        guard archivedRecordingIDs.insert(recordingID).inserted else { return }
        saveArchivedRecordingIDs()
        refreshVisibleRecordings()
        showTransientMessage("Archived transcript")
    }

    func unarchiveRecording(_ recordingID: String) {
        guard archivedRecordingIDs.remove(recordingID) != nil else { return }
        saveArchivedRecordingIDs()
        refreshVisibleRecordings()
        showTransientMessage("Unarchived transcript")
    }

    func toggleArchiveRecording(_ recordingID: String) {
        if isArchived(recordingID: recordingID) {
            unarchiveRecording(recordingID)
        } else {
            archiveRecording(recordingID)
        }
    }

    func archiveSelectedRecording() {
        guard let selectedRecordingID else { return }
        archiveRecording(selectedRecordingID)
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
                    recordingTitle: recording.source.voiceMemoTitle,
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
                autoApplySuggestedRecordingTitleIfNeeded(report.title, for: recording)
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
                return
            }
            _ = applyDefaultRecordingsFolder(showFeedback: false)
        } catch {
            errorBanner = "Could not restore saved folder. Choose a folder again."
        }
    }

    @discardableResult
    private func applyDefaultRecordingsFolder(showFeedback: Bool) -> Bool {
        let defaultURL = Self.defaultRecordingsFolderURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: defaultURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        do {
            try bookmarkStore.save(folderURL: defaultURL)
        } catch {
            errorBanner = "Using default folder for this session, but couldn't save permission: \(error.localizedDescription)"
        }

        setFolder(defaultURL)
        scanFolder()

        if showFeedback {
            showTransientMessage("Reset folder to default Voice Memos Recordings")
        }

        return true
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
        let previousRecordingIDs = Set(allRecordings.map(\.id))

        Task {
            do {
                let initialResult = try await Task.detached(priority: .userInitiated) {
                    try await useCase.execute(
                        folderURL: folderToScan,
                        offset: 0,
                        limit: Self.initialScanBatchSize
                    )
                }.value

                allRecordings = initialResult.recordings
                pruneEditedTranscriptOverrides()
                scanSummary = initialResult
                failures = initialResult.failures
                refreshVisibleRecordings()
                autoSelectNewestNewRecordingIfAvailable(previousRecordingIDs: previousRecordingIDs)

                if selectedRecordingID == nil {
                    selectedRecordingID = visibleRecordings.first?.id
                }

                progressText = "Loading more transcripts..."
                progressFraction = nil

                let remainingResult = try await Task.detached(priority: .utility) {
                    try await useCase.execute(
                        folderURL: folderToScan,
                        offset: Self.initialScanBatchSize
                    )
                }.value

                let mergedResult = mergeScanResults(primary: initialResult, secondary: remainingResult)
                allRecordings = mergedResult.recordings
                pruneEditedTranscriptOverrides()
                scanSummary = mergedResult
                failures = mergedResult.failures
                refreshVisibleRecordings()
                autoSelectNewestNewRecordingIfAvailable(previousRecordingIDs: previousRecordingIDs)

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

    private func mergeScanResults(primary: ScanResult, secondary: ScanResult) -> ScanResult {
        var mergedRecordings: [RecordingItem] = []
        var seenRecordingIDs = Set<String>()

        for recording in primary.recordings + secondary.recordings {
            if seenRecordingIDs.insert(recording.id).inserted {
                mergedRecordings.append(recording)
            }
        }

        return ScanResult(
            recordings: mergedRecordings,
            failures: primary.failures + secondary.failures
        )
    }

    private func refreshVisibleRecordings() {
        let baseRecordings = showArchivedRecordings
            ? allRecordings
            : allRecordings.filter { !archivedRecordingIDs.contains($0.id) }
        let displayRecordings = baseRecordings.map(recordingWithEditedTranscript)

        visibleRecordings = searchUseCase.execute(
            recordings: displayRecordings,
            query: searchQuery,
            sort: sortOption
        )

        if let selectedRecordingID,
           !visibleRecordings.contains(where: { $0.id == selectedRecordingID }) {
            self.selectedRecordingID = visibleRecordings.first?.id
        }
    }

    private func autoSelectNewestNewRecordingIfAvailable(previousRecordingIDs: Set<String>) {
        let newVisibleRecordings = visibleRecordings.filter { !previousRecordingIDs.contains($0.id) }
        guard let newestNewRecording = newVisibleRecordings.max(by: { $0.source.effectiveDate < $1.source.effectiveDate }) else {
            return
        }
        guard selectedRecordingID != newestNewRecording.id else { return }

        selectedRecordingID = newestNewRecording.id
        if hasOpenAIAPIKey {
            analyzeSelectedTranscriptIfMissing()
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

    private func saveArchivedRecordingIDs() {
        defaults.set(Array(archivedRecordingIDs), forKey: Self.archivedRecordingIDsKey)
    }

    private func saveShowArchivedRecordings() {
        defaults.set(showArchivedRecordings, forKey: Self.showArchivedRecordingsKey)
    }

    private func saveIncludeArchivedInBulkExport() {
        defaults.set(includeArchivedInBulkExport, forKey: Self.includeArchivedInBulkExportKey)
    }

    private func saveAIReports() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(aiReportsByRecordingID) else { return }
        defaults.set(data, forKey: Self.aiReportsKey)
    }

    private func saveEditedTranscriptText() {
        defaults.set(editedTranscriptTextByRecordingID, forKey: Self.editedTranscriptTextKey)
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

    private func originalTranscriptText(for recordingID: String) -> String? {
        allRecordings.first(where: { $0.id == recordingID })?.transcript?.text
    }

    private func effectiveTranscriptText(for recording: RecordingItem) -> String? {
        if let edited = editedTranscriptTextByRecordingID[recording.id] {
            return edited
        }
        return recording.transcript?.text
    }

    private func recordingWithEditedTranscript(_ recording: RecordingItem) -> RecordingItem {
        guard let transcript = recording.transcript else { return recording }
        guard let effectiveText = effectiveTranscriptText(for: recording), effectiveText != transcript.text else {
            return recording
        }
        return RecordingItem(
            source: recording.source,
            transcript: TranscriptData(
                text: effectiveText,
                jsonPayload: transcript.jsonPayload,
                localeIdentifier: transcript.localeIdentifier
            ),
            status: recording.status,
            scanIndex: recording.scanIndex,
            errorMessage: recording.errorMessage
        )
    }

    private func pruneEditedTranscriptOverrides() {
        let validIDs = Set(allRecordings.map(\.id))
        let filtered = editedTranscriptTextByRecordingID.filter { validIDs.contains($0.key) }
        guard filtered.count != editedTranscriptTextByRecordingID.count else { return }
        editedTranscriptTextByRecordingID = filtered
        saveEditedTranscriptText()
    }

    private func format(report: AITranscriptReport) -> String {
        var blocks: [String] = []

        if let title = report.title {
            blocks.append("Title\n\(title)")
        }

        blocks.append("Summary\n\(report.summary)")

        if let score = report.score {
            blocks.append("Score\n\(score)/10")
        }

        if !report.actionItems.isEmpty {
            let actionItems = report.actionItems.map { "• \($0)" }.joined(separator: "\n")
            blocks.append("Action Items\n\(actionItems)")
        }

        if !report.strengths.isEmpty {
            let strengths = report.strengths.map { "• \($0)" }.joined(separator: "\n")
            blocks.append("Strengths\n\(strengths)")
        }

        if !report.improvements.isEmpty {
            let improvements = report.improvements.map { "• \($0)" }.joined(separator: "\n")
            blocks.append("Improvements\n\(improvements)")
        }

        return blocks.joined(separator: "\n\n")
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

    private static func loadEditedTranscriptText(defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: Self.editedTranscriptTextKey) as? [String: String] ?? [:]
    }

    private static func loadAIAnalysisPrompt(defaults: UserDefaults) -> String {
        let prompt = defaults.string(forKey: Self.aiAnalysisPromptKey) ?? OpenAITranscriptAnalyzer.defaultSystemPrompt
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? OpenAITranscriptAnalyzer.defaultSystemPrompt
            : prompt
    }

    private static func loadArchivedRecordingIDs(defaults: UserDefaults) -> Set<String> {
        let ids = defaults.stringArray(forKey: Self.archivedRecordingIDsKey) ?? []
        return Set(ids)
    }

    private static func loadShowArchivedRecordings(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: Self.showArchivedRecordingsKey)
    }

    private static func loadIncludeArchivedInBulkExport(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: Self.includeArchivedInBulkExportKey)
    }
}
