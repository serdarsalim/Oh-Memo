import Domain
import SwiftUI

public struct TranscriptDetailView: View {
    private let recording: RecordingItem?
    private let activeQuery: String

    public init(recording: RecordingItem?, activeQuery: String) {
        self.recording = recording
        self.activeQuery = activeQuery
    }

    public var body: some View {
        Group {
            if let recording {
                content(for: recording)
            } else {
                ContentUnavailableView(
                    "Select a Recording",
                    systemImage: "waveform",
                    description: Text("Choose a row on the left to view transcript content.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for recording: RecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(recording.source.fileName)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 12) {
                    Label(Self.dateFormatter.string(from: recording.source.effectiveDate), systemImage: "calendar")
                    if let locale = recording.transcript?.localeIdentifier {
                        Label(locale, systemImage: "globe")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Divider()

            if let transcript = recording.transcript {
                ScrollView {
                    Text(transcript.text)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .scrollContentBackground(.hidden)

                if !activeQuery.isEmpty {
                    Text("Filtering by content query: \"\(activeQuery)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    recording.status == .failed ? "Extraction Failed" : "No Transcript",
                    systemImage: recording.status == .failed ? "exclamationmark.triangle" : "nosign",
                    description: Text(recording.errorMessage ?? "No transcript data available for this file.")
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
        )
        .padding(14)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter
    }()
}

public struct RecordingInspectorView: View {
    private let recording: RecordingItem?

    public init(recording: RecordingItem?) {
        self.recording = recording
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recording {
                Text("Details")
                    .font(.headline)

                keyValue("Filename", recording.source.fileName)
                keyValue("Status", recording.status.rawValue)
                keyValue("Path", recording.source.fileURL.path)
                keyValue("Recorded", Self.dateFormatter.string(from: recording.source.effectiveDate))

                if let transcript = recording.transcript {
                    keyValue("Characters", "\(transcript.text.count)")
                    if let locale = transcript.localeIdentifier {
                        keyValue("Locale", locale)
                    }
                }

                Spacer()
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.right",
                    description: Text("Select a recording to see metadata.")
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
