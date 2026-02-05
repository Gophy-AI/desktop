import Foundation
import Dispatch

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
        modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.textGenerationEngine = textGenerationEngine
        self.embeddingEngine = embeddingEngine
        self.ocrEngine = ocrEngine
        self.modelRegistry = modelRegistry

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
    }

    deinit {
        memoryPressureSource?.cancel()
        stateContinuation?.finish()
    }

    public func switchMode(_ mode: Mode) async throws {
        if mode == _currentMode {
            return
        }

        let isInitialLoad = _currentMode == nil

        if isInitialLoad {
            setState(.loading)
        } else {
            setState(.switching)
            try await unloadCurrentMode()
        }

        _currentMode = mode

        do {
            try await loadMode(mode)
            setState(.ready)
        } catch {
            setState(.error(error.localizedDescription))
            throw error
        }
    }

    private func loadMode(_ mode: Mode) async throws {
        if !embeddingEngine.isLoaded {
            try await embeddingEngine.load()
        }

        switch mode {
        case .meeting:
            try await transcriptionEngine.load()
            try await textGenerationEngine.load()

        case .document:
            try await ocrEngine.load()
        }
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
