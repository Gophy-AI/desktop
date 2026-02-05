import SwiftUI

@MainActor
struct DocumentDetailView: View {
    let document: DocumentRecord
    let onBack: () -> Void
    let onDelete: (DocumentRecord) -> Void

    @State private var viewModel: DocumentDetailViewModel?
    @State private var showDeleteConfirmation: Bool = false

    var body: some View {
        Group {
            if let viewModel = viewModel {
                VStack(spacing: 0) {
                    headerView(viewModel: viewModel)

                    Divider()

                    if let errorMessage = viewModel.errorMessage {
                        errorView(message: errorMessage, viewModel: viewModel)
                    }

                    if viewModel.chunks.isEmpty && viewModel.errorMessage == nil {
                        emptyStateView
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(viewModel.chunks.enumerated()), id: \.element.id) { index, chunk in
                                    ChunkView(chunk: chunk, index: index)
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .task {
                    await viewModel.loadChunks(documentId: document.id)
                }
                .confirmationDialog(
                    "Delete Document",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        onDelete(document)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to delete this document? This will remove the document, all chunks, and vectors.")
                }
            } else {
                SwiftUI.ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await initializeViewModel()
        }
    }

    private func headerView(viewModel: DocumentDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Image(systemName: typeIcon(for: document.type))
                    .font(.largeTitle)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 12) {
                        statusBadge

                        if document.pageCount > 0 {
                            Text("\(document.pageCount) pages")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(viewModel.formatDate(document.createdAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("\(viewModel.chunks.count) chunks")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .padding()
    }

    private var statusBadge: some View {
        Group {
            switch document.status {
            case "ready":
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            case "processing":
                Label("Processing", systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            case "failed":
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            default:
                Label("Pending", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Content")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This document has no chunks yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String, viewModel: DocumentDetailViewModel) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
            Spacer()
            Button("Dismiss") {
                viewModel.errorMessage = nil
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }

    private func typeIcon(for type: String) -> String {
        switch type.lowercased() {
        case "pdf":
            return "doc.fill"
        case "png", "jpg", "jpeg":
            return "photo"
        case "txt", "md":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private func initializeViewModel() async {
        guard viewModel == nil else { return }

        do {
            let storageManager = StorageManager()
            let database = try GophyDatabase(storageManager: storageManager)
            let documentRepo = DocumentRepository(database: database)

            viewModel = DocumentDetailViewModel(documentRepository: documentRepo)
        } catch {
            print("Failed to initialize DocumentDetailView: \(error)")
        }
    }
}

@MainActor
struct ChunkView: View {
    let chunk: DocumentChunkRecord
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chunk \(index)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if chunk.pageNumber > 0 {
                    Text("Page \(chunk.pageNumber)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }

                Spacer()
            }

            Text(chunk.content)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
