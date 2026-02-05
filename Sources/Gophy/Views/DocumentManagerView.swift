import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DocumentManagerView: View {
    @State private var viewModel: DocumentManagerViewModel?
    @State private var selectedDocument: DocumentRecord?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                NavigationStack {
                    if selectedDocument == nil {
                        documentListView(viewModel: viewModel)
                    } else {
                        DocumentDetailView(
                            document: selectedDocument!,
                            onBack: { selectedDocument = nil },
                            onDelete: { doc in
                                Task {
                                    await viewModel.deleteDocument(doc)
                                    selectedDocument = nil
                                }
                            }
                        )
                    }
                }
                .task {
                    await viewModel.loadDocuments()
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

    private func documentListView(viewModel: DocumentManagerViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Documents")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    viewModel.openFilePicker()
                }) {
                    Label("Add Document", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)
            }
            .padding()

            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }

            if viewModel.isProcessing {
                HStack {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing document...")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            if viewModel.documents.isEmpty && !viewModel.isProcessing {
                emptyStateView
            } else {
                List {
                    ForEach(viewModel.documents, id: \.id) { document in
                        DocumentRowView(
                            document: document,
                            viewModel: viewModel,
                            onSelect: { selectedDocument = document }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteDocument(document)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers, viewModel: viewModel)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Documents")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add documents to index and search them in chat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(providers: [NSItemProvider], viewModel: DocumentManagerViewModel) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else {
                        return
                    }

                    let ext = url.pathExtension.lowercased()
                    guard ["pdf", "png", "jpg", "jpeg", "txt", "md"].contains(ext) else {
                        return
                    }

                    Task { @MainActor in
                        await viewModel.processDocument(url: url)
                    }
                }
                handled = true
            }
        }

        return handled
    }

    private func initializeViewModel() async {
        guard viewModel == nil else { return }

        do {
            let storageManager = StorageManager()
            let database = try GophyDatabase(storageManager: storageManager)
            let documentRepo = DocumentRepository(database: database)
            let meetingRepo = MeetingRepository(database: database)

            guard (ModelRegistry.shared.availableModels().first(where: { $0.type == .embedding })) != nil else {
                return
            }

            guard (ModelRegistry.shared.availableModels().first(where: { $0.type == .ocr })) != nil else {
                return
            }

            let embeddingEngine = EmbeddingEngine()
            let ocrEngine = OCREngine()

            if !embeddingEngine.isLoaded {
                try await embeddingEngine.load()
            }

            let ocrEngineLoaded = await ocrEngine.isLoaded
            if !ocrEngineLoaded {
                try await ocrEngine.load()
            }

            let vectorSearchService = VectorSearchService(database: database)
            let embeddingPipeline = EmbeddingPipeline(
                embeddingEngine: embeddingEngine,
                vectorSearchService: vectorSearchService,
                meetingRepository: meetingRepo,
                documentRepository: documentRepo
            )

            let documentProcessor = DocumentProcessor(
                documentRepository: documentRepo,
                ocrEngine: ocrEngine,
                embeddingPipeline: embeddingPipeline
            )

            viewModel = DocumentManagerViewModel(
                documentRepository: documentRepo,
                documentProcessor: documentProcessor
            )
        } catch {
            print("Failed to initialize DocumentManagerView: \(error)")
        }
    }
}

@MainActor
struct DocumentRowView: View {
    let document: DocumentRecord
    let viewModel: DocumentManagerViewModel
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.typeIcon(for: document.type))
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        statusBadge
                        if document.pageCount > 0 {
                            Text("\(document.pageCount) pages")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(viewModel.formatDate(document.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if document.status == "processing" {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Group {
            switch document.status {
            case "ready":
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case "processing":
                Label("Processing", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case "failed":
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            default:
                Label("Pending", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
