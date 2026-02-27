import Domain
import SwiftUI

struct AIAssistantSidebarView: View {
    let recording: RecordingItem?
    let report: CachedAITranscriptReport?
    let isAnalyzing: Bool
    let errorMessage: String?
    let hasAPIKey: Bool
    let onRegenerate: () -> Void
    let onCopy: () -> Void
    let onEditPrompt: () -> Void
    let onOpenSettings: () -> Void

    private let bodyFont: Font = .system(size: 17)
    private let headingFont: Font = .system(size: 17, weight: .semibold)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Assistant")
                    .font(.headline)
                Spacer()
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

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

                if let analyzedAt = report?.analyzedAt {
                    Text("Last analyzed: \(Self.timeFormatter.string(from: analyzedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !hasAPIKey {
                Button("Set OpenAI API Key", action: onOpenSettings)
                    .buttonStyle(.link)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let report = report?.report {
                        summarySection(report)
                        section("Action Items", bullets: report.actionItems)
                        section("What went well", bullets: report.strengths)
                        section("What to improve", bullets: report.improvements)
                    } else {
                        ContentUnavailableView(
                            "No Analysis Yet",
                            systemImage: "sparkles",
                            description: Text("Switch to AI view to auto-analyze the selected transcript.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func summarySection(_ report: AITranscriptReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(headingFont)

            Text(report.summary)
                .font(bodyFont)
                .textSelection(.enabled)

            HStack(alignment: .center, spacing: 10) {
                Text("Conversion sentiment")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                ConversionSentimentBar(score: report.score)

                Text("\(clampedScore(report.score))/10")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(report.sentiment)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(headingFont)
            if bullets.isEmpty {
                Text("None")
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
            } else {
                Text(bulletedText(from: bullets))
                    .font(bodyFont)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
}

private struct ConversionSentimentBar: View {
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
