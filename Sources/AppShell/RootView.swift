import Domain
import FeatureExport
import FeatureRecordings
import FeatureTranscriptViewer
import SwiftUI

struct RootView: View {
    @StateObject private var model: AppModel
    @Environment(\.colorScheme) private var systemColorScheme

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
        }
        .preferredColorScheme(model.preferredColorScheme)
        .sheet(isPresented: $model.isShowingFailures) {
            FailureListSheet(failures: model.failures)
        }
        .onAppear {
            model.onAppear()
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
            NavigationSplitView {
                RecordingsSidebarView(
                    searchQuery: $model.searchQuery,
                    selectedRecordingID: $model.selectedRecordingID,
                    recordings: model.visibleRecordings
                )
                .navigationTitle("Recordings")
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
            } detail: {
                HSplitView {
                    TranscriptDetailView(
                        recording: model.selectedRecording,
                        activeQuery: model.searchQuery
                    )
                    .layoutPriority(1)

                    RecordingInspectorView(recording: model.selectedRecording)
                        .frame(minWidth: 280, idealWidth: 310, maxWidth: 360)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .safeAreaInset(edge: .bottom) {
                ExportActionBar(
                    summary: model.scanSummary,
                    isBusy: model.isScanning,
                    folderPath: model.folderPathDescription,
                    trailingView: AnyView(AppearanceFooterToggle(selection: $model.appearanceMode)),
                    onCopyCurrent: model.copyCurrentTranscript,
                    onCopyAll: model.copyAllTranscripts,
                    onExportText: model.exportText,
                    onExportJSON: model.exportJSON,
                    onShowErrors: model.showFailures
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Change Folder", action: model.chooseFolder)
                    Button("Rescan", action: model.rescan)
                        .disabled(model.isScanning)
                }

                ToolbarItem(placement: .automatic) {
                    Picker("Sort", selection: $model.sortOption) {
                        ForEach(RecordingSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text(model.folderName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if model.isScanning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 420)
                }
            }
            .overlay(alignment: .top) {
                if let banner = model.errorBanner {
                    ErrorBanner(text: banner) {
                        model.dismissError()
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private var firstRunView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 22) {
                Text("Voice Memo Transcripts")
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
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.90, green: 0.93, blue: 0.99)
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

private struct ErrorBanner: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", action: onClose)
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
