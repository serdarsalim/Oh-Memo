import Domain
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct TranscriptDetailView: View {
    private let recording: RecordingItem?
    private let onCopyTranscript: (RecordingItem) -> Void
    private let isDetailsVisible: Bool
    private let onToggleDetails: () -> Void
    @State private var descriptionsByRecordingID: [String: String] = [:]
    @State private var copiedRecordingID: String?

    public init(
        recording: RecordingItem?,
        onCopyTranscript: @escaping (RecordingItem) -> Void,
        isDetailsVisible: Bool,
        onToggleDetails: @escaping () -> Void
    ) {
        self.recording = recording
        self.onCopyTranscript = onCopyTranscript
        self.isDetailsVisible = isDetailsVisible
        self.onToggleDetails = onToggleDetails
    }

    public var body: some View {
        Group {
            if let recording {
                content(for: recording)
            } else {
                ContentUnavailableView(
                    "Select a Recording",
                    systemImage: "waveform",
                    description: Text("Choose a row on the left to view transcript content.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for recording: RecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    TextField("Add description", text: descriptionBinding(for: recording))
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)

                    Label(Self.inlineDateFormatter.string(from: recording.source.effectiveDate), systemImage: "calendar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(Self.dateFormatter.string(from: recording.source.effectiveDate))

                    Button {
                        onCopyTranscript(recording)
                        copiedRecordingID = recording.id
                        Task {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            if copiedRecordingID == recording.id {
                                copiedRecordingID = nil
                            }
                        }
                    } label: {
                        Image(systemName: copiedRecordingID == recording.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(copiedRecordingID == recording.id ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(copiedRecordingID == recording.id ? "Copied" : "Copy transcript")
                    .accessibilityLabel(copiedRecordingID == recording.id ? "Copied" : "Copy transcript")

                    Button(action: onToggleDetails) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(isDetailsVisible ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isDetailsVisible ? "Hide Details" : "Show Details")
                    .accessibilityLabel(isDetailsVisible ? "Hide Details" : "Show Details")
                }
            }

            Divider()

            if let transcript = recording.transcript {
                SelectableTranscriptTextView(text: transcript.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    recording.status == .failed ? "Extraction Failed" : "No Transcript",
                    systemImage: recording.status == .failed ? "exclamationmark.triangle" : "nosign",
                    description: Text(recording.errorMessage ?? "No transcript data available for this file.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func descriptionBinding(for recording: RecordingItem) -> Binding<String> {
        Binding(
            get: { descriptionsByRecordingID[recording.id] ?? "" },
            set: { descriptionsByRecordingID[recording.id] = $0 }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let inlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

public struct RecordingInspectorView: View {
    private let recording: RecordingItem?

    public init(recording: RecordingItem?) {
        self.recording = recording
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recording {
                Text("Details")
                    .font(.headline)

                keyValue("Filename", recording.source.fileName)
                keyValue("Status", recording.status.rawValue)

                if let transcript = recording.transcript {
                    keyValue("Characters", "\(transcript.text.count)")
                }

                Spacer()
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.right",
                    description: Text("Select a recording to see metadata.")
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

}

#if os(macOS)
private struct SelectableTranscriptTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}
#endif
