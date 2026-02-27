import Data
import Domain
import Foundation
import Platform
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import Darwin
#endif

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

    private let scanUseCase: ScanRecordingsUseCase
    private let searchUseCase: SearchTranscriptsUseCase
    private let exportUseCase: ExportTranscriptsUseCase
    private let bookmarkStore: FolderBookmarkStore
    private let folderPicker: FolderPickerClient
    private let clipboard: ClipboardClient
    private let saveClient: FileSaveClient
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

    init(
        scanUseCase: ScanRecordingsUseCase,
        searchUseCase: SearchTranscriptsUseCase,
        exportUseCase: ExportTranscriptsUseCase,
        bookmarkStore: FolderBookmarkStore,
        folderPicker: FolderPickerClient,
        clipboard: ClipboardClient,
        saveClient: FileSaveClient,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.appearanceMode = Self.loadAppearanceMode(defaults: defaults)
        self.scanUseCase = scanUseCase
        self.searchUseCase = searchUseCase
        self.exportUseCase = exportUseCase
        self.bookmarkStore = bookmarkStore
        self.folderPicker = folderPicker
        self.clipboard = clipboard
        self.saveClient = saveClient
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

    private static func loadAppearanceMode(defaults: UserDefaults) -> AppearanceMode {
        guard
            let rawValue = defaults.string(forKey: Self.appearanceModeKey),
            let mode = AppearanceMode(rawValue: rawValue)
        else {
            return .system
        }
        return mode
    }
}
