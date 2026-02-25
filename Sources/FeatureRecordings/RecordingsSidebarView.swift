import Domain
import SwiftUI

public struct RecordingsSidebarView: View {
    @Binding private var searchQuery: String
    @Binding private var selectedRecordingID: String?
    private let recordings: [RecordingItem]

    public init(
        searchQuery: Binding<String>,
        selectedRecordingID: Binding<String?>,
        recordings: [RecordingItem]
    ) {
        _searchQuery = searchQuery
        _selectedRecordingID = selectedRecordingID
        self.recordings = recordings
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcript content", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.35))
            )
            .padding([.top, .horizontal], 12)

            if recordings.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try another transcript keyword or clear search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                List(recordings, selection: $selectedRecordingID) { item in
                    RecordingRowView(item: item)
                        .tag(item.id)
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct RecordingRowView: View {
    let item: RecordingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.snippet)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: item.source.effectiveDate))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Label(statusLabel, systemImage: statusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLabel: String {
        switch item.status {
        case .ready:
            return "Ready"
        case .missing:
            return "No Transcript"
        case .failed:
            return "Error"
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .ready:
            return "checkmark.circle.fill"
        case .missing:
            return "minus.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .ready:
            return .green
        case .missing:
            return .orange
        case .failed:
            return .red
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
