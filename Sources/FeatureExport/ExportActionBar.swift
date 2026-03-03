import Domain
import SwiftUI

public struct ExportActionBar: View {
    private let summary: ScanResult?
    private let isBusy: Bool
    private let folderName: String
    private let leadingView: AnyView?
    private let trailingView: AnyView?
    private let onOpenFolder: () -> Void
    private let onChangeFolder: () -> Void
    private let onRescan: () -> Void
    private let onCopyAll: () -> Void
    private let onExportText: () -> Void

    public init(
        summary: ScanResult?,
        isBusy: Bool,
        folderName: String,
        leadingView: AnyView? = nil,
        trailingView: AnyView? = nil,
        onOpenFolder: @escaping () -> Void,
        onChangeFolder: @escaping () -> Void,
        onRescan: @escaping () -> Void,
        onCopyAll: @escaping () -> Void,
        onExportText: @escaping () -> Void
    ) {
        self.summary = summary
        self.isBusy = isBusy
        self.folderName = folderName
        self.leadingView = leadingView
        self.trailingView = trailingView
        self.onOpenFolder = onOpenFolder
        self.onChangeFolder = onChangeFolder
        self.onRescan = onRescan
        self.onCopyAll = onCopyAll
        self.onExportText = onExportText
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let leadingView {
                leadingView
            }

            Button(action: onRescan) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Rescan")
                .disabled(isBusy)

            Menu {
                Button("Copy All to Clipboard", action: onCopyAll)
                Button("Download as TXT", action: onExportText)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Export All")
            .disabled(isBusy)

            Button(action: onChangeFolder) {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Change Folder", action: onChangeFolder)
                Button("Open in Finder", action: onOpenFolder)
            }
            .help("Change recordings folder (right-click for more options)")

            Text("/\(folderName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let summary {
                SummaryPill(label: "Total", value: summary.readyCount, color: .green)
            }

            Spacer()

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
