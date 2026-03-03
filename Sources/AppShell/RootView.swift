import Domain
import FeatureExport
import FeatureRecordings
import FeatureTranscriptViewer
import SwiftUI

fileprivate enum CenterPaneMode {
    case transcript
    case aiAssistant
}

struct RootView: View {
    @StateObject private var model: AppModel
    @State private var centerPaneMode: CenterPaneMode = .aiAssistant
    @Environment(\.colorScheme) private var systemColorScheme
    private let sidebarWidth: CGFloat = 302

    init(model: AppModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .preferredColorScheme(model.preferredColorScheme)
        .sheet(isPresented: $model.isShowingFailures) {
            FailureListSheet(failures: model.failures)
        }
        .sheet(isPresented: $model.isShowingAISettings) {
            AISettingsSheet(
                keyMask: model.openAIAPIKeyMask,
                hasSavedKey: model.hasOpenAIAPIKey,
                defaultRecordingsFolderPath: model.defaultRecordingsFolderPath,
                showArchivedRecordings: $model.showArchivedRecordings,
                includeArchivedInBulkExport: $model.includeArchivedInBulkExport,
                onSave: model.saveOpenAIAPIKey,
                onResetFolderToDefault: model.resetFolderToDefaultRecordings
            )
        }
        .sheet(isPresented: $model.isShowingAIPromptEditor) {
            AIPromptEditorSheet(
                prompt: model.aiAnalysisPrompt,
                defaultPrompt: model.defaultAIAnalysisPrompt,
                onSave: model.saveAIAnalysisPrompt,
                onResetToDefault: model.resetAIAnalysisPromptToDefault
            )
        }
        .onAppear {
            model.onAppear()
        }
        .onChange(of: centerPaneMode) { _, newMode in
            guard newMode == .aiAssistant else { return }
            model.analyzeSelectedTranscriptIfMissing()
        }
        .onChange(of: model.selectedRecordingID) { _, _ in
            guard centerPaneMode == .aiAssistant else { return }
            model.analyzeSelectedTranscriptIfMissing()
        }
        .overlay(alignment: .topTrailing) {
            if let message = model.transientMessage {
                ToastView(text: message)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    .onTapGesture {
                        model.dismissMessage()
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.folderURL == nil {
            firstRunView
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    RecordingsSidebarView(
                        searchQuery: $model.searchQuery,
                        selectedRecordingID: $model.selectedRecordingID,
                        isScanning: model.isScanning,
                        progressText: model.progressText,
                        recordings: model.visibleRecordings,
                        descriptionsByRecordingID: model.descriptionsByRecordingID,
                        archivedRecordingIDs: Set(model.visibleRecordings.map(\.id).filter { model.isArchived(recordingID: $0) }),
                        onDescriptionChange: { recordingID, description in
                            model.setDescription(description, for: recordingID)
                        },
                        onArchiveToggle: model.toggleArchiveRecording,
                        onArchiveSelected: model.archiveSelectedRecording
                    )
                    .frame(width: sidebarWidth)

                    Divider()

                    centerPane
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                ExportActionBar(
                    summary: model.scanSummary,
                    isBusy: model.isScanning,
                    folderName: model.folderName,
                    leadingView: AnyView(
                        Picker("Sort", selection: $model.sortOption) {
                            ForEach(RecordingSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    ),
                    trailingView: AnyView(
                        FooterControls(
                            appearanceMode: $model.appearanceMode,
                            onOpenSettings: { model.isShowingAISettings = true }
                        )
                    ),
                    onOpenFolder: model.openCurrentFolderInFinder,
                    onChangeFolder: model.chooseFolder,
                    onRescan: model.rescan,
                    onCopyAll: model.copyAllTranscripts,
                    onExportText: model.exportText
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var centerPane: some View {
        HStack(alignment: .top, spacing: 12) {
            switch centerPaneMode {
            case .transcript:
                TranscriptDetailView(
                    recording: model.selectedRecording,
                    descriptionTextForRecordingID: model.description(for:),
                    onDescriptionChange: { recordingID, description in
                        model.setDescription(description, for: recordingID)
                    },
                    isTranscriptEdited: model.isTranscriptEdited(for:),
                    onTranscriptChange: { recordingID, text in
                        model.setEditedTranscriptText(text, for: recordingID)
                    },
                    onRevertTranscript: { recordingID in
                        model.revertTranscriptToOriginal(for: recordingID)
                    },
                    onCopyTranscript: { _ in model.copyCurrentTranscript() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .aiAssistant:
                aiAssistantCard
            }

            CenterPaneModeRail(selection: $centerPaneMode)
                .padding(.top, 18)
        }
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var aiAssistantCard: some View {
        AIAssistantSidebarView(
            recording: model.selectedRecording,
            recordingTitle: selectedRecordingHeaderTitle,
            report: model.selectedAIReport,
            isAnalyzing: model.aiIsAnalyzing,
            errorMessage: model.aiAnalysisError,
            hasAPIKey: model.hasOpenAIAPIKey,
            onRegenerate: { model.analyzeSelectedTranscript(force: true) },
            onCopy: model.copySelectedAIReport,
            onEditPrompt: { model.isShowingAIPromptEditor = true },
            onOpenSettings: { model.isShowingAISettings = true }
        )
        .padding(18)
        .frame(maxWidth: 800, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var selectedRecordingHeaderTitle: String {
        guard let recording = model.selectedRecording else {
            return "No Recording Selected"
        }

        let descriptionText = model.description(for: recording.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if !descriptionText.isEmpty {
            return descriptionText
        }

        let voiceMemoTitle = recording.source.voiceMemoTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !voiceMemoTitle.isEmpty {
            return voiceMemoTitle
        }

        return recording.source.fileName
    }

    private var firstRunView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 22) {
                Text("Oh Memo")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Select your recordings folder once. The app remembers it and lets you scan, search transcript content, copy, and export.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: 640)

                Button("Select Recordings Folder") {
                    model.chooseFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Tip: typically under ~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 34)
            .background(cardBackgroundStyle, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(effectiveColorScheme == .dark ? 0.16 : 0.45), lineWidth: 1)
            )

            AppearanceFooterToggle(selection: $model.appearanceMode)
        }
        .padding(40)
    }

    private var effectiveColorScheme: ColorScheme {
        model.preferredColorScheme ?? systemColorScheme
    }

    private var backgroundGradientColors: [Color] {
        switch effectiveColorScheme {
        case .dark:
            return [
                Color(red: 0.09, green: 0.11, blue: 0.15),
                Color(red: 0.14, green: 0.10, blue: 0.18)
            ]
        case .light:
            return [
                Color(red: 0.97, green: 0.97, blue: 0.97),
                Color(red: 0.94, green: 0.94, blue: 0.94)
            ]
        @unknown default:
            return [Color(.windowBackgroundColor), Color(.underPageBackgroundColor)]
        }
    }

    private var cardBackgroundStyle: AnyShapeStyle {
        if effectiveColorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.06))
        }
        return AnyShapeStyle(Color.white.opacity(0.75))
    }
}

private struct CenterPaneModeRail: View {
    @Binding private var selection: CenterPaneMode

    init(selection: Binding<CenterPaneMode>) {
        _selection = selection
    }

    var body: some View {
        VStack(spacing: 6) {
            modeButton(
                icon: "doc.text",
                label: "Transcript",
                mode: .transcript
            )
            modeButton(
                icon: "sparkles",
                label: "AI Assistant",
                mode: .aiAssistant
            )
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private func modeButton(icon: String, label: String, mode: CenterPaneMode) -> some View {
        Button {
            selection = mode
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selection == mode ? Color.accentColor.opacity(0.24) : Color.clear)
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .frame(width: 56, height: 56)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct AppearanceFooterToggle: View {
    @Binding var selection: AppearanceMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(
                            Capsule()
                                .fill(selection == mode ? Color.primary.opacity(0.14) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct FooterControls: View {
    @Binding var appearanceMode: AppearanceMode
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AppearanceFooterToggle(selection: $appearanceMode)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("AI Settings")
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct AISettingsSheet: View {
    let keyMask: String
    let hasSavedKey: Bool
    let defaultRecordingsFolderPath: String
    @Binding var showArchivedRecordings: Bool
    @Binding var includeArchivedInBulkExport: Bool
    let onSave: (String) -> Void
    let onResetFolderToDefault: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""
    @State private var isReplacingSavedKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Settings")
                .font(.title3.weight(.semibold))

            Text("OpenAI API Key")
                .font(.headline)

            if hasSavedKey && !isReplacingSavedKey {
                Text("Saved key: \(keyMask)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Replace Key") {
                        isReplacingSavedKey = true
                        draftKey = ""
                    }

                    Button("Remove Key") {
                        onSave("")
                        draftKey = ""
                        isReplacingSavedKey = false
                    }
                }
            } else {
                Text(hasSavedKey ? "Enter a new key to replace the current key." : "No key saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("sk-...", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if saveIfNeeded(), hasSavedKey {
                            isReplacingSavedKey = false
                        }
                    }

                if hasSavedKey {
                    HStack {
                        Button("Cancel Replacement") {
                            draftKey = ""
                            isReplacingSavedKey = false
                        }

                        Spacer()

                        Button("Save New Key") {
                            if saveIfNeeded() {
                                isReplacingSavedKey = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    Text("Paste a key and close this window to save it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Show archived transcripts", isOn: $showArchivedRecordings)
                .toggleStyle(.switch)
            Text("When off, archived transcripts are hidden from the sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Include archived in Copy all / Export all", isOn: $includeArchivedInBulkExport)
                .toggleStyle(.switch)
            Text("Controls whether archived transcripts are included in bulk copy and export actions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Recordings Folder")
                    .font(.headline)
                Text(defaultRecordingsFolderPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("Reset to Default Recordings Folder") {
                    onResetFolderToDefault()
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    if !hasSavedKey {
                        saveIfNeeded()
                    }
                    draftKey = ""
                    isReplacingSavedKey = false
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @discardableResult
    private func saveIfNeeded() -> Bool {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        onSave(trimmed)
        draftKey = ""
        return true
    }
}

private struct AIPromptEditorSheet: View {
    let prompt: String
    let defaultPrompt: String
    let onSave: (String) -> Void
    let onResetToDefault: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftPrompt: String

    init(
        prompt: String,
        defaultPrompt: String,
        onSave: @escaping (String) -> Void,
        onResetToDefault: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.defaultPrompt = defaultPrompt
        self.onSave = onSave
        self.onResetToDefault = onResetToDefault
        _draftPrompt = State(initialValue: prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Analysis Prompt")
                .font(.title3.weight(.semibold))

            Text("Customize how analysis is generated. Changes persist across sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $draftPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 280)
                .padding(.horizontal, 8)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Available JSON fields")
                    .font(.caption.weight(.semibold))
                Text("Required: summary")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("Optional: title, actionItems, score, strengths, improvements")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("If AI returns title, it is applied as the recording name.")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reset Default") {
                    draftPrompt = defaultPrompt
                    onResetToDefault()
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave(draftPrompt)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 760, height: 634)
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThickMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
    }
}

private struct FailureListSheet: View {
    let failures: [ScanFailure]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(failures, id: \.self) { failure in
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.fileName)
                        .font(.headline)
                    Text(failure.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Failed Files")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
