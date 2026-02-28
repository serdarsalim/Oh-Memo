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
    @State private var centerPaneMode: CenterPaneMode = .transcript
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
                onSave: model.saveOpenAIAPIKey
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
                        recordings: model.visibleRecordings,
                        descriptionsByRecordingID: model.descriptionsByRecordingID,
                        onDescriptionChange: { recordingID, description in
                            model.setDescription(description, for: recordingID)
                        }
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
        VStack(spacing: 8) {
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
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private func modeButton(icon: String, label: String, mode: CenterPaneMode) -> some View {
        Button {
            selection = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(selection == mode ? Color.accentColor.opacity(0.24) : Color.clear)
                )
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
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Settings")
                .font(.title3.weight(.semibold))

            Text("OpenAI API Key")
                .font(.headline)
            Text(hasSavedKey ? "Saved key: \(keyMask)" : "No key saved")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("sk-...", text: $draftKey)
                .textFieldStyle(.roundedBorder)

            Text("Paste a new key to save. Leave empty and click Save to remove.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                Button("Save") {
                    onSave(draftKey)
                    draftKey = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
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
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

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
        .frame(width: 760, height: 480)
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
