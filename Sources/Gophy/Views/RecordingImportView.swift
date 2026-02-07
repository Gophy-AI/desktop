import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import os.log

private let importViewLogger = Logger(subsystem: "com.gophy.app", category: "RecordingImport")

@MainActor
@Observable
final class RecordingImportViewModel {
    private let meetingRepository: MeetingRepository
    private let storageManager: StorageManager

    var recordings: [MeetingRecord] = []
    var isLoading = false
    var errorMessage: String?
    var isImporting = false

    init(meetingRepository: MeetingRepository, storageManager: StorageManager) {
        self.meetingRepository = meetingRepository
        self.storageManager = storageManager
    }

    func loadRecordings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allMeetings = try await meetingRepository.listAll()
            recordings = allMeetings.filter { $0.mode == "playback" }
        } catch {
            errorMessage = "Failed to load recordings: \(error.localizedDescription)"
        }
    }

    func importFile(url: URL) async -> MeetingRecord? {
        isImporting = true
        defer { isImporting = false }

        do {
            let importer = AudioFileImporter()
            let info = try await importer.importFile(url: url)

            // Check for duplicate by filename
            let destDir = storageManager.recordingsDirectory
            let destURL = destDir.appendingPathComponent(url.lastPathComponent)

            if FileManager.default.fileExists(atPath: destURL.path) {
                // Check SHA256 to detect true duplicate
                let sourceHash = try hashFile(at: url)
                let destHash = try hashFile(at: destURL)
                if sourceHash == destHash {
                    errorMessage = "This file has already been imported."
                    return nil
                }
            }

            // Copy file to recordings directory
            if !FileManager.default.fileExists(atPath: destDir.path) {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            }

            let finalURL: URL
            if FileManager.default.fileExists(atPath: destURL.path) {
                // Append UUID suffix to avoid name collision
                let stem = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                finalURL = destDir.appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(8)).\(ext)")
            } else {
                finalURL = destURL
            }

            try FileManager.default.copyItem(at: url, to: finalURL)

            // Create meeting record
            let title = url.deletingPathExtension().lastPathComponent
            let meeting = MeetingRecord(
                id: UUID().uuidString,
                title: title,
                startedAt: Date(),
                endedAt: nil,
                mode: "playback",
                status: "imported",
                createdAt: Date(),
                sourceFilePath: finalURL.path,
                speakerCount: nil
            )

            try await meetingRepository.create(meeting)
            recordings.insert(meeting, at: 0)

            importViewLogger.info("Imported recording: \(title, privacy: .public), duration: \(String(format: "%.1f", info.duration), privacy: .public)s")

            return meeting
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteRecording(_ meeting: MeetingRecord) async {
        do {
            // Delete the audio file if it exists
            if let path = meeting.sourceFilePath {
                let fileURL = URL(fileURLWithPath: path)
                try? FileManager.default.removeItem(at: fileURL)
            }

            try await meetingRepository.delete(id: meeting.id)
            recordings.removeAll { $0.id == meeting.id }
        } catch {
            errorMessage = "Failed to delete recording: \(error.localizedDescription)"
        }
    }

    func formatDuration(_ meeting: MeetingRecord) -> String {
        guard let endedAt = meeting.endedAt else {
            return "Not processed"
        }
        let duration = Int(endedAt.timeIntervalSince(meeting.startedAt))
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func hashFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
struct RecordingImportView: View {
    @State private var viewModel: RecordingImportViewModel
    @State private var showDeleteConfirmation = false
    @State private var recordingToDelete: MeetingRecord?
    @State private var isDropTargeted = false
    let onOpenPlayback: (MeetingRecord) -> Void

    init(
        meetingRepository: MeetingRepository,
        storageManager: StorageManager,
        onOpenPlayback: @escaping (MeetingRecord) -> Void
    ) {
        self._viewModel = State(initialValue: RecordingImportViewModel(
            meetingRepository: meetingRepository,
            storageManager: storageManager
        ))
        self.onOpenPlayback = onOpenPlayback
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if viewModel.isLoading {
                loadingView
            } else if viewModel.recordings.isEmpty {
                emptyState
            } else {
                recordingList
            }
        }
        .task {
            await viewModel.loadRecordings()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .confirmationDialog(
            "Delete Recording",
            isPresented: $showDeleteConfirmation,
            presenting: recordingToDelete
        ) { recording in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteRecording(recording)
                    recordingToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                recordingToDelete = nil
            }
        } message: { recording in
            Text("Are you sure you want to delete '\(recording.title)'? The audio file and all associated data will be removed.")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recordings")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { openFilePicker() }) {
                    Label("Import Recording", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isImporting)
            }

            dropZone
        }
        .padding()
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

            Text("Drop audio files here")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("MP3, WAV, M4A, MP4, AIFF, FLAC")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                )
        )
        .background(isDropTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            SwiftUI.ProgressView()
                .controlSize(.large)
            Text("Loading recordings...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No recordings yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import an audio file to transcribe and analyze")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: { openFilePicker() }) {
                Label("Import Recording", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.recordings.enumerated()), id: \.element.id) { index, recording in
                    RecordingListRowView(
                        recording: recording,
                        onSelect: { onOpenPlayback(recording) },
                        onDelete: {
                            recordingToDelete = recording
                            showDeleteConfirmation = true
                        },
                        formatDuration: { viewModel.formatDuration(recording) },
                        formatDate: { viewModel.formatDate(recording.createdAt) }
                    )

                    if index < viewModel.recordings.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioFileImporter.supportedFormats.compactMap { ext in
            UTType(filenameExtension: ext)
        }
        panel.message = "Select an audio file to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            if let meeting = await viewModel.importFile(url: url) {
                onOpenPlayback(meeting)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { data, _ in
                guard let urlData = data as? Data,
                      let urlString = String(data: urlData, encoding: .utf8),
                      let url = URL(string: urlString) else { return }

                let ext = url.pathExtension.lowercased()
                guard AudioFileImporter.supportedFormats.contains(ext) else { return }

                Task { @MainActor in
                    if let meeting = await viewModel.importFile(url: url) {
                        onOpenPlayback(meeting)
                    }
                }
            }
        }
    }
}

@MainActor
struct RecordingListRowView: View {
    let recording: MeetingRecord
    let onSelect: () -> Void
    let onDelete: () -> Void
    let formatDuration: () -> String
    let formatDate: () -> String

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text(recording.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label(formatDate(), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(formatDuration(), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let count = recording.speakerCount {
                            Label("\(count) speakers", systemImage: "person.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        statusBadge
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var statusBadge: some View {
        Group {
            switch recording.status {
            case "imported":
                Label("Imported", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            case "active":
                Label("Processing", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case "completed":
                Label("Transcribed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            default:
                EmptyView()
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        var body: some View {
            Text("Preview not available")
        }
    }
    return PreviewWrapper()
}
