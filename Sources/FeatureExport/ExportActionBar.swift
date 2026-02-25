import Domain
import SwiftUI

public struct ExportActionBar: View {
    private let summary: ScanResult?
    private let isBusy: Bool
    private let folderPath: String
    private let trailingView: AnyView?
    private let onCopyCurrent: () -> Void
    private let onCopyAll: () -> Void
    private let onExportText: () -> Void
    private let onExportJSON: () -> Void
    private let onShowErrors: () -> Void

    public init(
        summary: ScanResult?,
        isBusy: Bool,
        folderPath: String,
        trailingView: AnyView? = nil,
        onCopyCurrent: @escaping () -> Void,
        onCopyAll: @escaping () -> Void,
        onExportText: @escaping () -> Void,
        onExportJSON: @escaping () -> Void,
        onShowErrors: @escaping () -> Void
    ) {
        self.summary = summary
        self.isBusy = isBusy
        self.folderPath = folderPath
        self.trailingView = trailingView
        self.onCopyCurrent = onCopyCurrent
        self.onCopyAll = onCopyAll
        self.onExportText = onExportText
        self.onExportJSON = onExportJSON
        self.onShowErrors = onShowErrors
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button("Copy Current", action: onCopyCurrent)
                .disabled(isBusy)

            Button("Copy All", action: onCopyAll)
                .disabled(isBusy)

            Button("Export TXT", action: onExportText)
                .disabled(isBusy)

            Button("Export JSON", action: onExportJSON)
                .disabled(isBusy)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folderPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let summary {
                HStack(spacing: 8) {
                    SummaryPill(label: "Total", value: summary.recordings.count, color: .secondary)
                    SummaryPill(label: "Ready", value: summary.readyCount, color: .green)
                    SummaryPill(label: "Missing", value: summary.missingCount, color: .orange)
                    if summary.failedCount > 0 {
                        Button(action: onShowErrors) {
                            SummaryPill(label: "Failed", value: summary.failedCount, color: .red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let trailingView {
                trailingView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct SummaryPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        Text("\(label): \(value)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
