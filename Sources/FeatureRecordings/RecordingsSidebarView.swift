import Domain
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct RecordingsSidebarView: View {
    @Binding private var searchQuery: String
    @Binding private var selectedRecordingID: String?
    private let recordings: [RecordingItem]
    private let descriptionsByRecordingID: [String: String]
    private let archivedRecordingIDs: Set<String>
    private let onDescriptionChange: (String, String) -> Void
    private let onArchiveToggle: (String) -> Void
    private let onArchiveSelected: () -> Void
    @State private var editingRecordingID: String?

    public init(
        searchQuery: Binding<String>,
        selectedRecordingID: Binding<String?>,
        recordings: [RecordingItem],
        descriptionsByRecordingID: [String: String],
        archivedRecordingIDs: Set<String>,
        onDescriptionChange: @escaping (String, String) -> Void,
        onArchiveToggle: @escaping (String) -> Void,
        onArchiveSelected: @escaping () -> Void
    ) {
        _searchQuery = searchQuery
        _selectedRecordingID = selectedRecordingID
        self.recordings = recordings
        self.descriptionsByRecordingID = descriptionsByRecordingID
        self.archivedRecordingIDs = archivedRecordingIDs
        self.onDescriptionChange = onDescriptionChange
        self.onArchiveToggle = onArchiveToggle
        self.onArchiveSelected = onArchiveSelected
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
#if os(macOS)
                ActivatingPlainTextField(text: $searchQuery, placeholder: "")
                    .frame(height: 30)
#else
                TextField("", text: $searchQuery)
                    .textFieldStyle(.plain)
#endif
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
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
                ScrollViewReader { proxy in
                    List(recordings, selection: $selectedRecordingID) { item in
                        RecordingRowView(
                            item: item,
                            isEditing: Binding(
                                get: { editingRecordingID == item.id },
                                set: { isEditing in
                                    if isEditing {
                                        editingRecordingID = item.id
                                    } else if editingRecordingID == item.id {
                                        editingRecordingID = nil
                                    }
                                }
                            ),
                            description: descriptionsByRecordingID[item.id] ?? "",
                            onDescriptionChange: { onDescriptionChange(item.id, $0) }
                        )
                            .id(item.id)
                            .tag(item.id)
                            .contextMenu {
                                Button(archivedRecordingIDs.contains(item.id) ? "Unarchive" : "Archive") {
                                    onArchiveToggle(item.id)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    .listStyle(.plain)
                    .onMoveCommand(perform: handleMoveCommand)
#if os(macOS)
                    .onDeleteCommand(perform: onArchiveSelected)
                    .onCommand(#selector(NSResponder.insertNewline(_:)), perform: handleReturnCommand)
#endif
                    .onChange(of: recordings.map(\.id)) { oldIDs, newIDs in
                        guard newIDs.count > oldIDs.count, let firstID = newIDs.first else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                }
            }
        }
        .onChange(of: selectedRecordingID) { _, newSelection in
            if editingRecordingID != newSelection {
                editingRecordingID = nil
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

    private func handleReturnCommand() {
        guard let selectedRecordingID else {
            return
        }

        if editingRecordingID == selectedRecordingID {
            editingRecordingID = nil
        } else {
            editingRecordingID = selectedRecordingID
        }
    }
}

private struct RecordingRowView: View {
    let item: RecordingItem
    @Binding var isEditing: Bool
    let description: String
    let onDescriptionChange: (String) -> Void

    @State private var draftDescription = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextField("Add description", text: $draftDescription)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .focused($isRenameFieldFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            isRenameFieldFocused = true
                        }
                    }
                    .onSubmit {
                        finishEditing()
                    }
                    .onChange(of: isRenameFieldFocused) { _, focused in
                        if !focused {
                            finishEditing()
                        }
                    }
            } else {
                Text(primaryText)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        beginEditing()
                    }
            }

            Text(RecordingDateDisplay.timelineLabel(for: item.source.effectiveDate))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onChange(of: isEditing) { _, editing in
            if editing {
                draftDescription = editableSeedText
            }
        }
    }

    private var primaryText: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let title = item.source.voiceMemoTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty {
            return title
        }

        return item.snippet
    }

    private func beginEditing() {
        draftDescription = editableSeedText
        isEditing = true
    }

    private func finishEditing() {
        onDescriptionChange(draftDescription)
        isRenameFieldFocused = false
        isEditing = false
    }

    private var editableSeedText: String {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            return description
        }

        let trimmedVoiceMemoTitle = item.source.voiceMemoTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedVoiceMemoTitle.isEmpty {
            return trimmedVoiceMemoTitle
        }

        return ""
    }
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
        textField.focusRingType = .none
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
