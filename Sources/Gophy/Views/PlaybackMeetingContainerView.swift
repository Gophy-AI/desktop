import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "PlaybackMeetingContainer")

@MainActor
struct PlaybackMeetingContainerView: View {
    let meeting: MeetingRecord
    let fileURL: URL
    let onDismiss: () -> Void

    @State private var viewModel: PlaybackMeetingViewModel?
    @State private var initError: String?

    var body: some View {
        Group {
            if let errorMessage = initError {
                errorView(message: errorMessage)
            } else if let viewModel = viewModel {
                PlaybackMeetingView(viewModel: viewModel, onDismiss: onDismiss)
            } else {
                VStack(spacing: 16) {
                    SwiftUI.ProgressView()
                        .controlSize(.large)
                    Text("Preparing playback...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await initializeViewModel()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Playback Error")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Close") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func initializeViewModel() async {
        guard viewModel == nil, initError == nil else { return }

        do {
            let storageManager = StorageManager()
            let database = try GophyDatabase(storageManager: storageManager)
            let meetingRepo = MeetingRepository(database: database)
            let chatRepo = ChatMessageRepository(database: database)
            let documentRepo = DocumentRepository(database: database)

            // Check required models
            guard (ModelRegistry.shared.availableModels().first(where: { $0.type == .stt })) != nil else {
                initError = "Transcription model not downloaded. Download a speech-to-text model to process recordings."
                return
            }

            // Create engines
            let transcriptionEngine = TranscriptionEngine()
            let textGenerationEngine = TextGenerationEngine()
            let embeddingEngine = EmbeddingEngine()

            // Load transcription engine (required)
            if !transcriptionEngine.isLoaded {
                try await transcriptionEngine.load()
            }

            // Create playback service
            let playbackService = RecordingPlaybackService()

            // Create VAD filter and transcription pipeline
            let vadFilter = VADFilter()
            let transcriptionPipeline = TranscriptionPipeline(
                transcriptionEngine: transcriptionEngine,
                vadFilter: vadFilter
            )

            // Create vector search and embedding pipeline
            let vectorSearchService = VectorSearchService(database: database)
            let embeddingPipeline = EmbeddingPipeline(
                embeddingEngine: embeddingEngine,
                vectorSearchService: vectorSearchService,
                meetingRepository: meetingRepo,
                documentRepository: documentRepo
            )

            // Create session controller
            let sessionController = PlaybackSessionController(
                playbackService: playbackService,
                transcriptionPipeline: transcriptionPipeline,
                meetingRepository: meetingRepo,
                embeddingPipeline: embeddingPipeline
            )

            // Create suggestion engine
            let suggestionEngine = SuggestionEngine(
                textGenerationEngine: textGenerationEngine,
                vectorSearchService: vectorSearchService,
                embeddingEngine: embeddingEngine,
                meetingRepository: meetingRepo,
                documentRepository: documentRepo,
                chatMessageRepository: chatRepo
            )

            viewModel = PlaybackMeetingViewModel(
                meeting: meeting,
                fileURL: fileURL,
                sessionController: sessionController,
                meetingRepository: meetingRepo,
                suggestionEngine: suggestionEngine,
                chatMessageRepository: chatRepo
            )

            logger.info("Playback initialization complete")
        } catch {
            logger.error("Playback initialization failed: \(error.localizedDescription, privacy: .public)")
            initError = "Failed to initialize playback: \(error.localizedDescription)"
        }
    }
}
