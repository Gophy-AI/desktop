import SwiftUI

@MainActor
struct ChatView: View {
    @State private var viewModel: ChatViewModel?
    @State private var showClearConfirmation: Bool = false

    var body: some View {
        Group {
            if let viewModel = viewModel {
                VStack(spacing: 0) {
                    headerView(viewModel: viewModel)

                    Divider()

                    if let errorMessage = viewModel.errorMessage {
                        errorView(message: errorMessage, viewModel: viewModel)
                    }

                    if viewModel.messages.isEmpty {
                        emptyStateView
                    } else {
                        messageListView(viewModel: viewModel)
                    }

                    Divider()

                    inputView(viewModel: viewModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .confirmationDialog(
                    "Clear Chat",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All Messages", role: .destructive) {
                        Task {
                            await viewModel.clearMessages()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to clear all chat messages?")
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

    private func headerView(viewModel: ChatViewModel) -> some View {
        HStack {
            Text("Chat")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            Picker("Scope", selection: Binding(
                get: { viewModel.selectedScope },
                set: { viewModel.selectedScope = $0 }
            )) {
                Text("All").tag(RAGScope.all)
                Text("Meetings").tag(RAGScope.meetings)
                Text("Documents").tag(RAGScope.documents)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .disabled(viewModel.isGenerating)

            Button(action: {
                showClearConfirmation = true
            }) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.messages.isEmpty || viewModel.isGenerating)
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Ask a Question")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Ask a question about your meetings or documents")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageListView(viewModel: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isGenerating {
                        HStack {
                            SwiftUI.ProgressView()
                                .scaleEffect(0.7)
                            Text("Generating...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func inputView(viewModel: ChatViewModel) -> some View {
        HStack(spacing: 12) {
            TextField("Type your question...", text: Binding(
                get: { viewModel.inputText },
                set: { viewModel.inputText = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .lineLimit(1...5)
            .onSubmit {
                Task {
                    await viewModel.sendMessage()
                }
            }
            .disabled(viewModel.isGenerating)

            Button(action: {
                Task {
                    await viewModel.sendMessage()
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend(viewModel) ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend(viewModel))
        }
        .padding()
    }

    private func errorView(message: String, viewModel: ChatViewModel) -> some View {
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

    private func canSend(_ viewModel: ChatViewModel) -> Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isGenerating
    }

    private func initializeViewModel() async {
        guard viewModel == nil else { return }

        do {
            let storageManager = StorageManager()
            let database = try GophyDatabase(storageManager: storageManager)
            let documentRepo = DocumentRepository(database: database)
            let meetingRepo = MeetingRepository(database: database)
            let chatRepo = ChatMessageRepository(database: database)

            let embeddingEngine = EmbeddingEngine()
            let textGenEngine = TextGenerationEngine()

            if !embeddingEngine.isLoaded {
                try await embeddingEngine.load()
            }

            if !textGenEngine.isLoaded {
                try await textGenEngine.load()
            }

            let vectorSearchService = VectorSearchService(database: database)

            let ragPipeline = RAGPipeline(
                embeddingEngine: embeddingEngine,
                vectorSearchService: vectorSearchService,
                textGenerationEngine: textGenEngine,
                meetingRepository: meetingRepo,
                documentRepository: documentRepo
            )

            viewModel = ChatViewModel(
                ragPipeline: ragPipeline,
                chatMessageRepository: chatRepo
            )
        } catch {
            print("Failed to initialize ChatView: \(error)")
        }
    }
}
