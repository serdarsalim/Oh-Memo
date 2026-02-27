import Domain
import SwiftUI
#if os(macOS)
import AppKit
import AVFoundation
#endif

public struct TranscriptDetailView: View {
    private let recording: RecordingItem?
    private let onCopyTranscript: (RecordingItem) -> Void
    private let isDetailsVisible: Bool
    private let onToggleDetails: () -> Void
    private let maxContentWidth: CGFloat = 800
    @StateObject private var audioPlayer = InlineAudioPlayer()
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
        .onChange(of: recording?.id, initial: true) { _, _ in
            configureAudioPlayerForCurrentRecording()
        }
        .onDisappear {
            audioPlayer.stopAndReset()
        }
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

                HStack(spacing: 10) {
                    Button(action: audioPlayer.togglePlayPause) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!audioPlayer.canPlay)

                    Slider(
                        value: Binding(
                            get: { audioPlayer.currentTime },
                            set: { audioPlayer.seek(to: $0) }
                        ),
                        in: 0...max(audioPlayer.duration, 1),
                        onEditingChanged: { isEditing in
                            if isEditing {
                                audioPlayer.pauseProgressUpdatesForSeeking()
                            } else {
                                audioPlayer.resumeProgressUpdatesAfterSeeking()
                            }
                        }
                    )
                    .disabled(!audioPlayer.canPlay)

                    Text(audioPlayer.playbackTimeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .trailing)
                }
            }

            Divider()

            if let transcript = recording.transcript {
                SelectableTranscriptTextView(text: formattedTranscriptForDisplay(transcript.text))
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
        .frame(maxWidth: maxContentWidth, maxHeight: .infinity, alignment: .topLeading)
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

    private func formattedTranscriptForDisplay(_ rawText: String) -> String {
        let normalized = rawText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return rawText }

        return normalized.replacingOccurrences(
            of: #"([.!?])\s+"#,
            with: "$1\n",
            options: .regularExpression
        )
    }

    private func configureAudioPlayerForCurrentRecording() {
        guard let recording else {
            audioPlayer.stopAndReset()
            return
        }
        audioPlayer.load(url: recording.source.fileURL)
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
@MainActor
private final class InlineAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var loadedURL: URL?
    private var progressTask: Task<Void, Never>?

    var canPlay: Bool {
        audioPlayer != nil && duration > 0
    }

    var playbackTimeLabel: String {
        "\(format(seconds: currentTime)) / \(format(seconds: duration))"
    }

    func load(url: URL) {
        guard loadedURL != url else {
            return
        }

        stopAndReset()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()

            audioPlayer = player
            loadedURL = url
            duration = max(player.duration, 0)
            currentTime = 0
            isPlaying = false
        } catch {
            audioPlayer = nil
            loadedURL = url
            duration = 0
            currentTime = 0
            isPlaying = false
        }
    }

    func togglePlayPause() {
        guard let player = audioPlayer else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
            stopProgressUpdates()
            return
        }

        if player.currentTime >= player.duration {
            player.currentTime = 0
            currentTime = 0
        }

        if player.play() {
            isPlaying = true
            startProgressUpdates()
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clamped = max(0, min(seconds, duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    func pauseProgressUpdatesForSeeking() {
        stopProgressUpdates()
    }

    func resumeProgressUpdatesAfterSeeking() {
        if isPlaying {
            startProgressUpdates()
        }
    }

    func stopAndReset() {
        stopProgressUpdates()
        audioPlayer?.stop()
        audioPlayer = nil
        loadedURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func startProgressUpdates() {
        stopProgressUpdates()
        progressTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.refreshProgress()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func refreshProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        duration = max(player.duration, 0)

        if !player.isPlaying {
            if currentTime >= max(duration - 0.05, 0) {
                currentTime = duration
            }
            isPlaying = false
            stopProgressUpdates()
        }
    }

    private func format(seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let wholeSeconds = Int(max(0, seconds))
        let minutes = wholeSeconds / 60
        let remainder = wholeSeconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

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
