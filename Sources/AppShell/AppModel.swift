import Data
import Domain
import Foundation
import Platform
import SwiftUI
import UniformTypeIdentifiers

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

    func copyCurrentTranscript() {
        guard let selected = selectedRecording, let text = selected.transcript?.text, !text.isEmpty else {
            transientMessage = "No transcript selected to copy."
            return
        }

        clipboard.setString(text)
        transientMessage = "Copied current transcript"
    }

    func copyAllTranscripts() {
        let merged = exportUseCase.mergedText(for: allRecordings)
        guard !merged.isEmpty else {
            transientMessage = "No transcript content to copy"
            return
        }

        clipboard.setString(merged)
        transientMessage = "Copied all transcripts"
    }

    func exportText() {
        let merged = exportUseCase.mergedText(for: allRecordings)
        guard let data = merged.data(using: .utf8), !data.isEmpty else {
            transientMessage = "No transcript content to export"
            return
        }

        do {
            _ = try saveClient.save(
                data: data,
                suggestedFileName: "voice-memo-transcripts.txt",
                contentType: .plainText
            )
            transientMessage = "Exported TXT"
        } catch {
            errorBanner = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportJSON() {
        do {
            let data = try exportUseCase.mergedJSON(for: allRecordings)
            guard !data.isEmpty else {
                transientMessage = "No transcript content to export"
                return
            }

            _ = try saveClient.save(
                data: data,
                suggestedFileName: "voice-memo-transcripts.json",
                contentType: .json
            )
            transientMessage = "Exported JSON"
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
        if let current = securityScopedURL {
            current.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }

        _ = folder.startAccessingSecurityScopedResource()
        securityScopedURL = folder
        folderURL = folder
    }

    private func scanFolder() {
        guard let folderURL else {
            return
        }

        isScanning = true
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
