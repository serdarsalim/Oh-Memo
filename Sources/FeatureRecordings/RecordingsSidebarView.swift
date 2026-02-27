import Domain
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
#if os(macOS)
                ActivatingPlainTextField(text: $searchQuery, placeholder: "Search")
#else
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
#endif
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

#if os(macOS)
private struct ActivatingPlainTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ActivatingNSTextField {
        let textField = ActivatingNSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .default
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: ActivatingNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: ActivatingPlainTextField

        init(_ parent: ActivatingPlainTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}

private final class ActivatingNSTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
        window?.makeFirstResponder(currentEditor() ?? self)
    }

    override func becomeFirstResponder() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        return super.becomeFirstResponder()
    }
}
#endif
