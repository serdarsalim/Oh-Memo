import Domain
import SwiftUI

public struct ExportActionBar: View {
    private let summary: ScanResult?
    private let isBusy: Bool
    private let folderName: String
    private let trailingView: AnyView?
    private let onOpenFolder: () -> Void
    private let onChangeFolder: () -> Void
    private let onRescan: () -> Void
    private let onExportText: () -> Void
    private let onShowErrors: () -> Void

    public init(
        summary: ScanResult?,
        isBusy: Bool,
        folderName: String,
        trailingView: AnyView? = nil,
        onOpenFolder: @escaping () -> Void,
        onChangeFolder: @escaping () -> Void,
        onRescan: @escaping () -> Void,
        onExportText: @escaping () -> Void,
        onShowErrors: @escaping () -> Void
    ) {
        self.summary = summary
        self.isBusy = isBusy
        self.folderName = folderName
        self.trailingView = trailingView
        self.onOpenFolder = onOpenFolder
        self.onChangeFolder = onChangeFolder
        self.onRescan = onRescan
        self.onExportText = onExportText
        self.onShowErrors = onShowErrors
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button("Rescan", action: onRescan)
                .disabled(isBusy)

            Button("Export All", action: onExportText)
                .disabled(isBusy)

            Button(action: onOpenFolder) {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Open in Finder", action: onOpenFolder)
                Button("Change Folder", action: onChangeFolder)
            }
            .help("Open folder (right-click for more options)")

            Text("/\(folderName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let summary {
                HStack(spacing: 8) {
                    SummaryPill(label: "Total", value: summary.recordings.count, color: .secondary)
                    SummaryPill(label: "Ready", value: summary.readyCount, color: .green)
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
