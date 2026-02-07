import Foundation
import Dispatch
import os.log

private let modeLogger = Logger(subsystem: "com.gophy.app", category: "ModeController")

public enum Mode: Sendable, Equatable {
    case meeting
    case document
}

public protocol TranscriptionEngineProtocol: Sendable {
    var isLoaded: Bool { get }
    func load() async throws
    func unload()
}

public protocol TextGenerationEngineProtocol: Sendable {
    var isLoaded: Bool { get }
    func load() async throws
    func unload()
}

public protocol EmbeddingEngineProtocol: Sendable {
    var isLoaded: Bool { get }
    func load() async throws
    func unload()
}

public protocol OCREngineActorProtocol: Sendable {
    var isLoaded: Bool { get async }
    func load() async throws
    func unload() async
}

extension TranscriptionEngine: TranscriptionEngineProtocol {}
extension TextGenerationEngine: TextGenerationEngineProtocol {}
extension EmbeddingEngine: EmbeddingEngineProtocol {}
extension OCREngine: OCREngineActorProtocol {}

public final class ModeController: @unchecked Sendable {
    private let transcriptionEngine: any TranscriptionEngineProtocol
    private let textGenerationEngine: any TextGenerationEngineProtocol
    private let embeddingEngine: any EmbeddingEngineProtocol
    private let ocrEngine: any OCREngineActorProtocol
    private let modelRegistry: any ModelRegistryProtocol
    private let providerRegistry: ProviderRegistry?
    private var providerChangeTask: Task<Void, Never>?

    private var _currentMode: Mode?
    private var _currentState: ModeState = .idle
    private var stateContinuation: AsyncStream<ModeState>.Continuation?
    private let memoryPressureSource: DispatchSourceMemoryPressure?

    public private(set) var currentMode: Mode? {
        get { _currentMode }
        set { _currentMode = newValue }
    }

    public var isReady: Bool {
        if case .ready = _currentState {
            return true
        }
        return false
    }

    public let stateStream: AsyncStream<ModeState>

    public init(
        transcriptionEngine: any TranscriptionEngineProtocol,
        textGenerationEngine: any TextGenerationEngineProtocol,
        embeddingEngine: any EmbeddingEngineProtocol,
        ocrEngine: any OCREngineActorProtocol,
        modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared,
        providerRegistry: ProviderRegistry? = nil
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.textGenerationEngine = textGenerationEngine
        self.embeddingEngine = embeddingEngine
        self.ocrEngine = ocrEngine
        self.modelRegistry = modelRegistry
        self.providerRegistry = providerRegistry

        var continuation: AsyncStream<ModeState>.Continuation?
        self.stateStream = AsyncStream { cont in
            continuation = cont
        }
        self.stateContinuation = continuation

        self.memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )

        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.handleMemoryPressure()
            }
        }
        memoryPressureSource?.resume()

        if let registry = providerRegistry {
            providerChangeTask = Task { [weak self] in
                for await capability in registry.providerChangeStream {
                    guard let self = self, let mode = self._currentMode else { continue }
                    modeLogger.info("Provider changed for \(capability.rawValue, privacy: .public), reloading mode")
                    try? await self.switchMode(mode == .meeting ? .document : .meeting)
                    try? await self.switchMode(mode)
                }
            }
        }
    }

    deinit {
        memoryPressureSource?.cancel()
        providerChangeTask?.cancel()
        stateContinuation?.finish()
    }

    public func switchMode(_ mode: Mode) async throws {
        modeLogger.info("switchMode called: \(String(describing: mode), privacy: .public)")

        if mode == _currentMode {
            modeLogger.info("Already in mode, returning")
            return
        }

        let isInitialLoad = _currentMode == nil

        if isInitialLoad {
            modeLogger.info("Initial load")
            setState(.loading)
        } else {
            modeLogger.info("Switching from existing mode")
            setState(.switching)
            try await unloadCurrentMode()
        }

        _currentMode = mode

        do {
            modeLogger.info("Loading mode...")
            try await loadMode(mode)
            modeLogger.info("Mode loaded successfully")
            setState(.ready)
        } catch {
            modeLogger.error("Mode load failed: \(error.localizedDescription, privacy: .public)")
            setState(.error(error.localizedDescription))
            throw error
        }
    }

    private func loadMode(_ mode: Mode) async throws {
        modeLogger.info("loadMode: \(String(describing: mode), privacy: .public)")
        CrashReporter.shared.logInfo("ModeController.loadMode(\(mode)) starting")

        let embeddingIsCloud = providerRegistry?.isCloudProvider(for: .embedding) ?? false

        // Only load embedding engine if using local provider and model is downloaded
        if !embeddingIsCloud,
           let embeddingModel = modelRegistry.availableModels().first(where: { $0.type == .embedding }),
           modelRegistry.isDownloaded(embeddingModel),
           !embeddingEngine.isLoaded {
            modeLogger.info("Loading embedding engine...")
            CrashReporter.shared.logInfo("About to load embedding engine (model: \(embeddingModel.name))")
            do {
                try await embeddingEngine.load()
                modeLogger.info("Embedding engine loaded")
                CrashReporter.shared.logInfo("Embedding engine loaded successfully in ModeController")
            } catch {
                CrashReporter.shared.logError(error, context: "ModeController - embedding engine load failed")
                modeLogger.error("Failed to load embedding engine: \(error.localizedDescription, privacy: .public)")
                // Don't throw - embedding is optional
            }
        } else if embeddingIsCloud {
            modeLogger.info("Skipping embedding engine (using cloud provider)")
        } else {
            modeLogger.info("Skipping embedding engine (not downloaded or already loaded)")
            CrashReporter.shared.logInfo("Skipping embedding engine load")
        }

        switch mode {
        case .meeting:
            let sttIsCloud = providerRegistry?.isCloudProvider(for: .speechToText) ?? false

            // Only load local transcription engine if using local provider
            if !sttIsCloud {
                if !transcriptionEngine.isLoaded {
                    modeLogger.info("Loading transcription engine...")
                    try await transcriptionEngine.load()
                    modeLogger.info("Transcription engine loaded")
                } else {
                    modeLogger.info("Transcription engine already loaded")
                }
            } else {
                modeLogger.info("Skipping transcription engine (using cloud STT provider)")
            }
            // Text generation is optional - skip to avoid memory pressure
            modeLogger.info("Skipping text generation engine (loaded on demand)")

        case .document:
            let visionIsCloud = providerRegistry?.isCloudProvider(for: .vision) ?? false

            if !visionIsCloud {
                let ocrLoaded = await ocrEngine.isLoaded
                if !ocrLoaded {
                    modeLogger.info("Loading OCR engine...")
                    try await ocrEngine.load()
                    modeLogger.info("OCR engine loaded")
                } else {
                    modeLogger.info("OCR engine already loaded")
                }
            } else {
                modeLogger.info("Skipping OCR engine (using cloud vision provider)")
            }
        }
        modeLogger.info("loadMode complete")
    }

    private func unloadCurrentMode() async throws {
        guard let currentMode = _currentMode else {
            return
        }

        switch currentMode {
        case .meeting:
            transcriptionEngine.unload()
            textGenerationEngine.unload()

        case .document:
            await ocrEngine.unload()
        }
    }

    private func handleMemoryPressure() async {
        guard let currentMode = _currentMode else {
            return
        }

        switch currentMode {
        case .meeting:
            if !textGenerationEngine.isLoaded && !transcriptionEngine.isLoaded {
                return
            }

        case .document:
            if !(await ocrEngine.isLoaded) {
                return
            }
        }
    }

    private func setState(_ state: ModeState) {
        _currentState = state
        stateContinuation?.yield(state)
    }
}
