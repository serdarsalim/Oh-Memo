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
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(
                Rectangle()
                    .fill(.white)
            )
            .padding([.top, .horizontal], 10)
            .padding(.bottom, 8)

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
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.plain)
                .onMoveCommand(perform: handleMoveCommand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard !recordings.isEmpty else { return }

        switch direction {
        case .up:
            selectPreviousRecording()
        case .down:
            selectNextRecording()
        default:
            break
        }
    }

    private func selectPreviousRecording() {
        guard !recordings.isEmpty else { return }

        guard
            let selectedRecordingID,
            let selectedIndex = recordings.firstIndex(where: { $0.id == selectedRecordingID })
        else {
            self.selectedRecordingID = recordings.last?.id
            return
        }

        let previousIndex = max(selectedIndex - 1, 0)
        self.selectedRecordingID = recordings[previousIndex].id
    }

    private func selectNextRecording() {
        guard !recordings.isEmpty else { return }

        guard
            let selectedRecordingID,
            let selectedIndex = recordings.firstIndex(where: { $0.id == selectedRecordingID })
        else {
            self.selectedRecordingID = recordings.first?.id
            return
        }

        let nextIndex = min(selectedIndex + 1, recordings.count - 1)
        self.selectedRecordingID = recordings[nextIndex].id
    }
}

private struct RecordingRowView: View {
    let item: RecordingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.snippet)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(2)

            Text(Self.dateFormatter.string(from: item.source.effectiveDate))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
