import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "MeetingContainer")

@MainActor
struct MeetingContainerView: View {
    @State private var viewModel: MeetingViewModel?
    @State private var initError: String?
    @State private var isInitializing = true
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if let errorMessage = initError {
                modelsRequiredView(message: errorMessage)
            } else if let viewModel = viewModel {
                MeetingView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                onDismiss()
                            }
                        }
                    }
            } else {
                VStack(spacing: 16) {
                    SwiftUI.ProgressView()
                        .controlSize(.large)
                    Text("Preparing meeting...")
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

    private func modelsRequiredView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Models Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Go to Models tab to download the required models.")
                .font(.caption)
                .foregroundStyle(.tertiary)

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
            logger.info("Starting meeting initialization...")

            let storageManager = StorageManager()
            logger.info("Created StorageManager")

            let database = try GophyDatabase(storageManager: storageManager)
            logger.info("Created database")

            let meetingRepo = MeetingRepository(database: database)
            let chatRepo = ChatMessageRepository(database: database)
            let documentRepo = DocumentRepository(database: database)
            logger.info("Created repositories")

            // Check required models
            guard (ModelRegistry.shared.availableModels().first(where: { $0.type == .stt })) != nil else {
                initError = "Transcription model not downloaded. Download a speech-to-text model to record meetings."
                return
            }
            logger.info("STT model available")

            // Create engines
            let transcriptionEngine = TranscriptionEngine()
            let textGenerationEngine = TextGenerationEngine()
            let embeddingEngine = EmbeddingEngine()
            logger.info("Created engines")

            // Load transcription engine (required)
            if !transcriptionEngine.isLoaded {
                logger.info("Loading transcription engine...")
                try await transcriptionEngine.load()
                logger.info("Transcription engine loaded")
            }

            // Skip loading text generation and embedding during meeting init
            // to avoid memory pressure. They load ~8GB combined with transcription.
            // Suggestions will work without them (just won't have RAG context).
            logger.info("Skipping text generation and embedding engines (loaded on-demand)")

            logger.info("Creating audio components...")
            // Create audio components (don't start yet - MeetingSessionController will start them)
            let micCapture = MicrophoneCaptureService()
            logger.info("Created MicrophoneCaptureService")

            let systemCapture = SystemAudioCaptureService()
            logger.info("Created SystemAudioCaptureService")

            // Create VAD filter
            let vadFilter = VADFilter()
            logger.info("Created VADFilter")

            // Create transcription pipeline
            let transcriptionPipeline = TranscriptionPipeline(
                transcriptionEngine: transcriptionEngine,
                vadFilter: vadFilter
            )
            logger.info("Created TranscriptionPipeline")

            // Create vector search and embedding pipeline
            let vectorSearchService = VectorSearchService(database: database)
            let embeddingPipeline = EmbeddingPipeline(
                embeddingEngine: embeddingEngine,
                vectorSearchService: vectorSearchService,
                meetingRepository: meetingRepo,
                documentRepository: documentRepo
            )
            logger.info("Created EmbeddingPipeline")

            // Create OCR engine for mode controller
            let ocrEngine = OCREngine()
            logger.info("Created OCREngine")

            // Create mode controller
            let modeController = ModeController(
                transcriptionEngine: transcriptionEngine,
                textGenerationEngine: textGenerationEngine,
                embeddingEngine: embeddingEngine,
                ocrEngine: ocrEngine
            )
            logger.info("Created ModeController")

            // Create suggestion engine
            let suggestionEngine = SuggestionEngine(
                textGenerationEngine: textGenerationEngine,
                vectorSearchService: vectorSearchService,
                embeddingEngine: embeddingEngine,
                meetingRepository: meetingRepo,
                documentRepository: documentRepo,
                chatMessageRepository: chatRepo
            )
            logger.info("Created SuggestionEngine")

            // Create session controller
            let sessionController = MeetingSessionController(
                modeController: modeController,
                transcriptionPipeline: transcriptionPipeline,
                meetingRepository: meetingRepo,
                embeddingPipeline: embeddingPipeline,
                microphoneCapture: micCapture,
                systemAudioCapture: systemCapture
            )
            logger.info("Created MeetingSessionController")

            viewModel = MeetingViewModel(
                sessionController: sessionController,
                suggestionEngine: suggestionEngine,
                chatMessageRepository: chatRepo
            )
            logger.info("Meeting initialization complete!")
        } catch {
            logger.error("Meeting initialization failed: \(error.localizedDescription, privacy: .public)")
            initError = "Failed to initialize meeting: \(error.localizedDescription)"
        }
    }
}
