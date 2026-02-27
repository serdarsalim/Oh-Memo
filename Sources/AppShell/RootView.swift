import Domain
import FeatureExport
import FeatureRecordings
import FeatureTranscriptViewer
import SwiftUI

struct RootView: View {
    @StateObject private var model: AppModel
    @State private var isDetailsVisible = false
    @State private var hasInitializedDetailsVisibility = false
    @Environment(\.colorScheme) private var systemColorScheme
    private static let detailsVisiblePreferenceKey = "voiceMemo.detailsVisible"
    private let sidebarWidth: CGFloat = 336
    private let detailsColumnWidth: CGFloat = 320

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
        .onAppear {
            model.onAppear()
            initializeDetailsVisibilityIfNeeded()
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
                        descriptionForRecordingID: model.description(for:)
                    )
                    .frame(width: sidebarWidth)

                    Divider()

                    HStack(spacing: 0) {
                        TranscriptDetailView(
                            recording: model.selectedRecording,
                            descriptionTextForRecordingID: model.description(for:),
                            onDescriptionChange: { recordingID, description in
                                model.setDescription(description, for: recordingID)
                            },
                            onCopyTranscript: { _ in model.copyCurrentTranscript() },
                            isDetailsVisible: isDetailsVisible,
                            onToggleDetails: toggleDetailsVisibility
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if isDetailsVisible {
                            Divider()
                            RecordingInspectorView(recording: model.selectedRecording)
                                .frame(width: detailsColumnWidth)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    trailingView: AnyView(AppearanceFooterToggle(selection: $model.appearanceMode)),
                    onOpenFolder: model.openCurrentFolderInFinder,
                    onChangeFolder: model.chooseFolder,
                    onRescan: model.rescan,
                    onExportText: model.exportText,
                    onShowErrors: model.showFailures
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var firstRunView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 22) {
                Text("Transcript Manager")
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

    private func initializeDetailsVisibilityIfNeeded() {
        guard !hasInitializedDetailsVisibility else { return }
        hasInitializedDetailsVisibility = true
        isDetailsVisible = UserDefaults.standard.bool(forKey: Self.detailsVisiblePreferenceKey)
    }

    private func toggleDetailsVisibility() {
        isDetailsVisible.toggle()
        if isDetailsVisible {
            UserDefaults.standard.set(true, forKey: Self.detailsVisiblePreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.detailsVisiblePreferenceKey)
        }
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
