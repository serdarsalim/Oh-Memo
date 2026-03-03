import Domain
import SwiftUI
#if os(macOS)
import AVFoundation
#endif

struct AIAssistantSidebarView: View {
    let recording: RecordingItem?
    let recordingTitle: String
    let report: CachedAITranscriptReport?
    let isAnalyzing: Bool
    let errorMessage: String?
    let hasAPIKey: Bool
    let providerDisplayName: String
    let onRegenerate: () -> Void
    let onCopy: () -> Void
    let onEditPrompt: () -> Void
    let onOpenSettings: () -> Void
    @StateObject private var audioPlayer = AIAssistantInlineAudioPlayer()

    private let bodyFont: Font = .system(size: 17)
    private let headingFont: Font = .system(size: 17, weight: .semibold)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recordingTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text("AI Assistant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Copy AI report")
                    .accessibilityLabel("Copy AI report")
                    .disabled(report == nil)

                    Button(action: onEditPrompt) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Edit analysis prompt")
                    .accessibilityLabel("Edit analysis prompt")

                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Re-analyze")
                    .accessibilityLabel("Re-analyze")
                    .disabled(recording == nil || isAnalyzing)

                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else if let analyzedAt = report?.analyzedAt {
                        Text("Last analyzed \(Self.timeFormatter.string(from: analyzedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !hasAPIKey {
                Button("Set \(providerDisplayName) API Key", action: onOpenSettings)
                    .buttonStyle(.link)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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
                .help("Play recording audio")

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

            Divider()

            if let report = report?.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summarySection(report)
                        if !report.actionItems.isEmpty {
                            section("Action Items", bullets: report.actionItems)
                        }
                        if !report.strengths.isEmpty {
                            section("Strengths", bullets: report.strengths)
                        }
                        if !report.improvements.isEmpty {
                            section("Improvements", bullets: report.improvements)
                        }
                        if let title = report.title {
                            Text("Suggested title: \(title)")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack {
                    Spacer()
                    ContentUnavailableView(
                        "No Analysis Yet",
                        systemImage: "sparkles",
                        description: Text("Switch to AI view to auto-analyze the selected transcript.")
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: recording?.id, initial: true) { _, _ in
            configureAudioPlayerForCurrentRecording()
        }
        .onDisappear {
            audioPlayer.stopAndReset()
        }
    }

    @ViewBuilder
    private func summarySection(_ report: AITranscriptReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(headingFont)

            Text(report.summary)
                .font(bodyFont)
                .textSelection(.enabled)

            if let score = report.score {
                HStack(alignment: .center, spacing: 10) {
                    Text("Score")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ScoreBar(score: score)

                    Text("\(clampedScore(score))/10")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(headingFont)
            Text(bulletedText(from: bullets))
                .font(bodyFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clampedScore(_ score: Int) -> Int {
        max(0, min(score, 10))
    }

    private func bulletedText(from bullets: [String]) -> String {
        bullets.map { "• \($0)" }.joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func configureAudioPlayerForCurrentRecording() {
        guard let recording else {
            audioPlayer.stopAndReset()
            return
        }
        audioPlayer.load(url: recording.source.fileURL)
    }
}

private struct ScoreBar: View {
    let score: Int

    private var clamped: Int {
        max(0, min(score, 10))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 10, id: \.self) { index in
                Capsule()
                    .fill(index < clamped ? Color.green.opacity(0.82) : Color.secondary.opacity(0.25))
                    .frame(width: 14, height: 7)
            }
        }
    }
}

#if os(macOS)
@MainActor
private final class AIAssistantInlineAudioPlayer: ObservableObject {
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

        if player.isPlaying {
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
        let clamped = min(max(seconds, 0), max(player.duration, 0))
        player.currentTime = clamped
        currentTime = clamped
    }

    func pauseProgressUpdatesForSeeking() {
        stopProgressUpdates()
    }

    func resumeProgressUpdatesAfterSeeking() {
        guard isPlaying else { return }
        startProgressUpdates()
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
            while let self {
                await MainActor.run {
                    self.syncProgress()
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func syncProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        duration = max(player.duration, 0)

        if !player.isPlaying {
            isPlaying = false
            stopProgressUpdates()
        }
    }

    private func format(seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
#endif
