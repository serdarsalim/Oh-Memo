import Domain
import SwiftUI

struct AIAssistantSidebarView: View {
    let recording: RecordingItem?
    let visibleSections: Set<AIReportSection>
    let report: CachedAITranscriptReport?
    let isAnalyzing: Bool
    let errorMessage: String?
    let hasAPIKey: Bool
    let onAnalyze: () -> Void
    let onRegenerate: () -> Void
    let onCopy: () -> Void
    let onToggleSection: (AIReportSection) -> Void
    let onOpenSettings: () -> Void

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
                Button("Analyze", action: onAnalyze)
                    .buttonStyle(.borderedProminent)
                    .disabled(recording == nil || isAnalyzing)

                Button("Copy", action: onCopy)
                    .buttonStyle(.bordered)
                    .disabled(report == nil)

                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(.bordered)
                    .disabled(recording == nil || isAnalyzing)
            }

            if !hasAPIKey {
                Button("Set OpenAI API Key", action: onOpenSettings)
                    .buttonStyle(.link)
            }

            Text("Show")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(AIReportSection.allCases) { section in
                    ToggleChip(
                        title: section.title,
                        isActive: visibleSections.contains(section),
                        action: { onToggleSection(section) }
                    )
                }
            }

            if let analyzedAt = report?.analyzedAt {
                Text("Last analyzed: \(Self.timeFormatter.string(from: analyzedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        if visibleSections.contains(.summary) {
                            section("Summary", body: report.summary)
                        }

                        if visibleSections.contains(.actionItems) {
                            section("Action Items", bullets: report.actionItems)
                        }

                        if visibleSections.contains(.sentiment) {
                            section("Sentiment", body: report.sentiment)
                        }

                        if visibleSections.contains(.score) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Score")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(report.score)/10")
                                    .font(.subheadline)
                                section("What went well", bullets: report.strengths)
                                section("What to improve", bullets: report.improvements)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "No Analysis Yet",
                            systemImage: "sparkles",
                            description: Text("Select a transcript and click Analyze.")
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
    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func section(_ title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if bullets.isEmpty {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, item in
                    Text("• \(item)")
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ToggleChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
