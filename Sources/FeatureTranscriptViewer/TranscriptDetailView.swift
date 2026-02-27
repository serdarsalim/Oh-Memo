import Domain
import SwiftUI
#if os(macOS)
import AppKit
import AVFoundation
#endif

public struct TranscriptDetailView: View {
    private let recording: RecordingItem?
    private let descriptionTextForRecordingID: (String) -> String
    private let onDescriptionChange: (String, String) -> Void
    private let onCopyTranscript: (RecordingItem) -> Void
    private let maxContentWidth: CGFloat = 800
    @StateObject private var audioPlayer = InlineAudioPlayer()
    @State private var copiedRecordingID: String?
    @State private var editingDescriptionRecordingID: String?
    @State private var descriptionDraft: String = ""
    @FocusState private var focusedDescriptionRecordingID: String?

    public init(
        recording: RecordingItem?,
        descriptionTextForRecordingID: @escaping (String) -> String,
        onDescriptionChange: @escaping (String, String) -> Void,
        onCopyTranscript: @escaping (RecordingItem) -> Void
    ) {
        self.recording = recording
        self.descriptionTextForRecordingID = descriptionTextForRecordingID
        self.onDescriptionChange = onDescriptionChange
        self.onCopyTranscript = onCopyTranscript
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
            editingDescriptionRecordingID = nil
            focusedDescriptionRecordingID = nil
        }
        .onChange(of: focusedDescriptionRecordingID) { _, newValue in
            if newValue == nil {
                endDescriptionEditing(saveChanges: true)
            }
        }
        .onDisappear {
            audioPlayer.stopAndReset()
        }
    }

    private func content(for recording: RecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    descriptionFieldOrTitle(for: recording)
                        .frame(height: 30)
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
                }
                .frame(minHeight: 44)

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
                SelectableTranscriptTextView(
                    attributedText: transcriptDisplayAttributedText(for: transcript)
                )
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
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func descriptionBinding(for recording: RecordingItem) -> Binding<String> {
        Binding(
            get: { descriptionTextForRecordingID(recording.id) },
            set: { onDescriptionChange(recording.id, $0) }
        )
    }

    @ViewBuilder
    private func descriptionFieldOrTitle(for recording: RecordingItem) -> some View {
        let displayTitle = displayDescriptionText(for: recording)
        let hasDisplayTitle = !displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if editingDescriptionRecordingID == recording.id {
            TextField("Add description", text: $descriptionDraft)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .focused($focusedDescriptionRecordingID, equals: recording.id)
                .onAppear {
                    DispatchQueue.main.async {
                        focusedDescriptionRecordingID = recording.id
                    }
                }
                .onSubmit {
                    endDescriptionEditing(saveChanges: true)
                }
        } else {
            Button {
                beginDescriptionEditing(for: recording.id)
            } label: {
                Text(hasDisplayTitle ? displayTitle : "Add description")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hasDisplayTitle ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func beginDescriptionEditing(for recordingID: String) {
        guard let recording else { return }
        descriptionDraft = displayDescriptionText(for: recording)
        editingDescriptionRecordingID = recordingID
        DispatchQueue.main.async {
            focusedDescriptionRecordingID = recordingID
        }
    }

    private func endDescriptionEditing(saveChanges: Bool) {
        if saveChanges, let recordingID = editingDescriptionRecordingID {
            onDescriptionChange(recordingID, descriptionDraft)
        }
        focusedDescriptionRecordingID = nil
        editingDescriptionRecordingID = nil
        descriptionDraft = ""
    }

    private func displayDescriptionText(for recording: RecordingItem) -> String {
        let description = descriptionTextForRecordingID(recording.id)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            return description
        }

        let voiceMemoTitle = recording.source.voiceMemoTitle ?? ""
        let trimmedVoiceMemoTitle = voiceMemoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedVoiceMemoTitle.isEmpty {
            return voiceMemoTitle
        }

        return ""
    }

    private func appleAttributedTranscript(from transcript: TranscriptData) -> NSAttributedString? {
        guard let jsonPayload = transcript.jsonPayload, let payloadData = jsonPayload.data(using: .utf8) else {
            return nil
        }

        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: payloadData),
            let root = jsonObject as? [String: Any],
            let attributedStringPayload = root["attributedString"]
        else {
            return nil
        }

        if let attributedDictionary = attributedStringPayload as? [String: Any],
           let runs = attributedDictionary["runs"] as? [Any] {
            return attributedStringFromRuns(runs)
        }

        if let runs = attributedStringPayload as? [Any] {
            return attributedStringFromRuns(runs)
        }

        if let plainString = attributedStringPayload as? String {
            return NSAttributedString(string: plainString)
        }

        return nil
    }

    private func transcriptDisplayAttributedText(for transcript: TranscriptData) -> NSAttributedString {
        if let appleAttributed = appleAttributedTranscript(from: transcript),
           hasMeaningfulTranscriptStructure(appleAttributed.string) {
            return appleAttributed
        }

        let formatted = fallbackFormattedTranscript(transcript.text)
        return NSAttributedString(string: formatted, attributes: baseTranscriptAttributes)
    }

    private func hasMeaningfulTranscriptStructure(_ text: String) -> Bool {
        let lineBreakCount = text.reduce(into: 0) { count, character in
            if character == "\n" {
                count += 1
            }
        }
        return lineBreakCount >= 3 || text.contains("\n\n")
    }

    private func fallbackFormattedTranscript(_ rawText: String) -> String {
        let normalized = rawText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return rawText }

        let sentenceMarker = "<__sentence_break__>"
        let marked = normalized.replacingOccurrences(
            of: #"([.!?])\s+"#,
            with: "$1\(sentenceMarker)",
            options: .regularExpression
        )

        let sentenceChunks = marked
            .components(separatedBy: sentenceMarker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sentenceChunks.isEmpty else { return normalized }

        var paragraphs: [String] = []
        var currentSentences: [String] = []
        var currentLength = 0

        for sentence in sentenceChunks {
            let projectedLength = currentLength + sentence.count + (currentSentences.isEmpty ? 0 : 1)
            if !currentSentences.isEmpty && (currentSentences.count >= 2 || projectedLength > 220) {
                paragraphs.append(currentSentences.joined(separator: " "))
                currentSentences = []
                currentLength = 0
            }

            currentSentences.append(sentence)
            currentLength += sentence.count + 1
        }

        if !currentSentences.isEmpty {
            paragraphs.append(currentSentences.joined(separator: " "))
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func attributedStringFromRuns(_ runs: [Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var activeAttributes = baseTranscriptAttributes

        for run in runs {
            if let text = run as? String {
                result.append(NSAttributedString(string: text, attributes: activeAttributes))
                continue
            }

            if let attributes = run as? [String: Any] {
                activeAttributes = baseTranscriptAttributes.merging(parsedTextAttributes(from: attributes)) { _, new in new }
            }
        }

        if result.length == 0 {
            return NSAttributedString(string: "")
        }

        return result
    }

    private func parsedTextAttributes(from rawAttributes: [String: Any]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]

        if let underline = integerValue(forAnyOf: ["underlineStyle", "NSUnderline", "underline"], in: rawAttributes) {
            attributes[.underlineStyle] = underline
        }

        if let strikethrough = integerValue(forAnyOf: ["strikethroughStyle", "NSStrikethrough", "strikethrough"], in: rawAttributes) {
            attributes[.strikethroughStyle] = strikethrough
        }

        if let kern = doubleValue(forAnyOf: ["kern", "NSKern"], in: rawAttributes) {
            attributes[.kern] = kern
        }

        if let baselineOffset = doubleValue(forAnyOf: ["baselineOffset", "NSBaselineOffset"], in: rawAttributes) {
            attributes[.baselineOffset] = baselineOffset
        }

        return attributes
    }

    private func integerValue(forAnyOf keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            if let intValue = dictionary[key] as? Int {
                return intValue
            }
            if let numberValue = dictionary[key] as? NSNumber {
                return numberValue.intValue
            }
        }
        return nil
    }

    private func doubleValue(forAnyOf keys: [String], in dictionary: [String: Any]) -> Double? {
        for key in keys {
            if let doubleValue = dictionary[key] as? Double {
                return doubleValue
            }
            if let numberValue = dictionary[key] as? NSNumber {
                return numberValue.doubleValue
            }
        }
        return nil
    }

    private var baseTranscriptAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
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
    let attributedText: NSAttributedString

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
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.attributedString() != attributedText {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }
}
#endif
