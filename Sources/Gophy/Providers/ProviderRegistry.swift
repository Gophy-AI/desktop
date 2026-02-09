import Foundation
@preconcurrency import CoreImage
import os.log

private let registryLogger = Logger(subsystem: "com.gophy.app", category: "ProviderRegistry")

public final class ProviderRegistry: @unchecked Sendable {

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let textGenProvider = "selectedTextGenProvider"
        static let textGenModel = "selectedTextGenModel"
        static let embeddingProvider = "selectedEmbeddingProvider"
        static let embeddingModel = "selectedEmbeddingModel"
        static let sttProvider = "selectedSTTProvider"
        static let sttModel = "selectedSTTModel"
        static let visionProvider = "selectedVisionProvider"
        static let visionModel = "selectedVisionModel"
        static let ttsProvider = "selectedTTSProvider"
        static let ttsModel = "selectedTTSModel"
    }

    // MARK: - Properties

    private let keychainService: any KeychainServiceProtocol
    private let userDefaults: UserDefaults

    private let transcriptionEngine: any TranscriptionEngineProtocol
    private let textGenerationEngine: any TextGenerationEngineProtocol
    private let embeddingEngine: any EmbeddingEngineProtocol
    private let ocrEngine: any OCREngineActorProtocol
    private let ttsEngine: (any TTSEngineProtocol)?

    private var changeContinuation: AsyncStream<ProviderCapability>.Continuation?
    public let providerChangeStream: AsyncStream<ProviderCapability>

    // Cached provider instances
    private var cachedTextGenProvider: (any TextGenerationProvider)?
    private var cachedEmbeddingProvider: (any EmbeddingProvider)?
    private var cachedSTTProvider: (any STTProvider)?
    private var cachedVisionProvider: (any VisionProvider)?
    private var cachedTTSProvider: (any TTSProvider)?

    // MARK: - Init

    public init(
        keychainService: any KeychainServiceProtocol = KeychainService(),
        userDefaults: UserDefaults = .standard,
        transcriptionEngine: any TranscriptionEngineProtocol,
        textGenerationEngine: any TextGenerationEngineProtocol,
        embeddingEngine: any EmbeddingEngineProtocol,
        ocrEngine: any OCREngineActorProtocol,
        ttsEngine: (any TTSEngineProtocol)? = nil
    ) {
        self.keychainService = keychainService
        self.userDefaults = userDefaults
        self.transcriptionEngine = transcriptionEngine
        self.textGenerationEngine = textGenerationEngine
        self.embeddingEngine = embeddingEngine
        self.ocrEngine = ocrEngine
        self.ttsEngine = ttsEngine

        var continuation: AsyncStream<ProviderCapability>.Continuation?
        self.providerChangeStream = AsyncStream { cont in
            continuation = cont
        }
        self.changeContinuation = continuation
    }

    deinit {
        changeContinuation?.finish()
    }

    // MARK: - Active Provider Accessors

    public func activeTextGenProvider() -> any TextGenerationProvider {
        if let cached = cachedTextGenProvider { return cached }
        let provider = buildProvider(for: .textGeneration) as? (any TextGenerationProvider)
            ?? buildLocalTextGenProvider()
        cachedTextGenProvider = provider
        return provider
    }

    public func activeEmbeddingProvider() -> any EmbeddingProvider {
        if let cached = cachedEmbeddingProvider { return cached }
        let provider = buildProvider(for: .embedding) as? (any EmbeddingProvider)
            ?? buildLocalEmbeddingProvider()
        cachedEmbeddingProvider = provider
        return provider
    }

    public func activeSTTProvider() -> any STTProvider {
        if let cached = cachedSTTProvider { return cached }
        let provider = buildProvider(for: .speechToText) as? (any STTProvider)
            ?? buildLocalSTTProvider()
        cachedSTTProvider = provider
        return provider
    }

    public func activeVisionProvider() -> any VisionProvider {
        if let cached = cachedVisionProvider { return cached }
        let provider = buildProvider(for: .vision) as? (any VisionProvider)
            ?? buildLocalVisionProvider()
        cachedVisionProvider = provider
        return provider
    }

    public func activeTTSProvider() -> (any TTSProvider)? {
        if let cached = cachedTTSProvider { return cached }
        guard let ttsEngine else { return nil }
        let provider = buildLocalTTSProvider(engine: ttsEngine)
        cachedTTSProvider = provider
        return provider
    }

    // MARK: - Configuration

    public func configureProvider(id: String, apiKey: String) throws {
        try keychainService.save(apiKey: apiKey, for: id)
        registryLogger.info("Configured provider: \(id, privacy: .public)")
    }

    public func removeProvider(id: String) throws {
        try keychainService.delete(for: id)
        registryLogger.info("Removed provider: \(id, privacy: .public)")

        // Revert any capabilities using this provider to local
        for capability in ProviderCapability.allCases {
            if selectedProviderId(for: capability) == id {
                selectProvider(for: capability, providerId: "local", modelId: "")
            }
        }
    }

    public func selectProvider(for capability: ProviderCapability, providerId: String, modelId: String) {
        let (providerKey, modelKey) = defaultsKeys(for: capability)
        userDefaults.set(providerId, forKey: providerKey)
        userDefaults.set(modelId, forKey: modelKey)

        invalidateCache(for: capability)
        changeContinuation?.yield(capability)

        registryLogger.info("Selected provider \(providerId, privacy: .public) for \(capability.rawValue, privacy: .public)")
    }

    public func configuredProviders() -> [String] {
        (try? keychainService.listProviderIds()) ?? []
    }

    public func selectedProviderId(for capability: ProviderCapability) -> String {
        let (providerKey, _) = defaultsKeys(for: capability)
        return userDefaults.string(forKey: providerKey) ?? "local"
    }

    public func selectedModelId(for capability: ProviderCapability) -> String {
        let (_, modelKey) = defaultsKeys(for: capability)
        return userDefaults.string(forKey: modelKey) ?? ""
    }

    public func isCloudProvider(for capability: ProviderCapability) -> Bool {
        selectedProviderId(for: capability) != "local"
    }

    // MARK: - Health Check

    public func checkHealth(providerId: String) async -> ProviderHealthStatus {
        guard providerId != "local" else {
            return .healthy
        }

        let apiKey: String
        do {
            guard let retrieved = try keychainService.retrieve(for: providerId), !retrieved.isEmpty else {
                return .unavailable("No API key configured")
            }
            apiKey = retrieved
        } catch {
            return .unavailable("Failed to retrieve API key")
        }

        if providerId == "anthropic" {
            let provider = AnthropicProvider(apiKey: apiKey)
            return await provider.healthCheck()
        }

        guard let config = ProviderCatalog.provider(id: providerId) else {
            return .unavailable("Unknown provider: \(providerId)")
        }

        let firstTextModel = config.availableModels.first { $0.capability == .textGeneration }?.id
        let firstEmbModel = config.availableModels.first { $0.capability == .embedding }?.id

        let provider = OpenAICompatibleProvider(
            providerId: config.id,
            baseURL: config.baseURL,
            apiKey: apiKey,
            textGenModel: firstTextModel,
            embeddingModel: firstEmbModel
        )
        return await provider.healthCheck()
    }

    // MARK: - Private Helpers

    private func defaultsKeys(for capability: ProviderCapability) -> (providerKey: String, modelKey: String) {
        switch capability {
        case .textGeneration:
            return (DefaultsKey.textGenProvider, DefaultsKey.textGenModel)
        case .embedding:
            return (DefaultsKey.embeddingProvider, DefaultsKey.embeddingModel)
        case .speechToText:
            return (DefaultsKey.sttProvider, DefaultsKey.sttModel)
        case .vision:
            return (DefaultsKey.visionProvider, DefaultsKey.visionModel)
        case .textToSpeech:
            return (DefaultsKey.ttsProvider, DefaultsKey.ttsModel)
        }
    }

    private func invalidateCache(for capability: ProviderCapability) {
        switch capability {
        case .textGeneration:
            cachedTextGenProvider = nil
        case .embedding:
            cachedEmbeddingProvider = nil
        case .speechToText:
            cachedSTTProvider = nil
        case .vision:
            cachedVisionProvider = nil
        case .textToSpeech:
            cachedTTSProvider = nil
        }
    }

    private func buildProvider(for capability: ProviderCapability) -> Any? {
        let providerId = selectedProviderId(for: capability)
        guard providerId != "local" else { return nil }

        let apiKey: String
        do {
            guard let retrieved = try keychainService.retrieve(for: providerId), !retrieved.isEmpty else {
                registryLogger.warning("No API key for provider \(providerId, privacy: .public), falling back to local")
                return nil
            }
            apiKey = retrieved
        } catch {
            registryLogger.warning("Failed to retrieve API key for \(providerId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let modelId = selectedModelId(for: capability)

        if providerId == "anthropic" {
            return buildAnthropicProvider(apiKey: apiKey, capability: capability, modelId: modelId)
        }

        guard let config = ProviderCatalog.provider(id: providerId) else {
            registryLogger.warning("Unknown provider ID: \(providerId, privacy: .public)")
            return nil
        }

        return buildOpenAICompatibleProvider(config: config, apiKey: apiKey, capability: capability, modelId: modelId)
    }

    private func buildAnthropicProvider(apiKey: String, capability: ProviderCapability, modelId: String) -> Any? {
        switch capability {
        case .textGeneration:
            return AnthropicProvider(apiKey: apiKey, textGenModel: modelId.isEmpty ? "claude-sonnet-4-5-20250929" : modelId)
        case .vision:
            return AnthropicProvider(apiKey: apiKey, visionModel: modelId.isEmpty ? "claude-sonnet-4-5-20250929" : modelId)
        case .embedding, .speechToText, .textToSpeech:
            return nil
        }
    }

    private func buildOpenAICompatibleProvider(config: ProviderConfiguration, apiKey: String, capability: ProviderCapability, modelId: String) -> Any? {
        let textGenModel: String? = capability == .textGeneration ? (modelId.isEmpty ? nil : modelId) : nil
        let embeddingModel: String? = capability == .embedding ? (modelId.isEmpty ? nil : modelId) : nil
        let sttModel: String? = capability == .speechToText ? (modelId.isEmpty ? nil : modelId) : nil
        let visionModel: String? = capability == .vision ? (modelId.isEmpty ? nil : modelId) : nil

        let dimensions: Int
        if let embModel = embeddingModel {
            if embModel.contains("3-large") {
                dimensions = 3072
            } else if embModel.contains("3-small") {
                dimensions = 1536
            } else {
                dimensions = 1536
            }
        } else {
            dimensions = 1536
        }

        return OpenAICompatibleProvider(
            providerId: config.id,
            baseURL: config.baseURL,
            apiKey: apiKey,
            textGenModel: textGenModel,
            embeddingModel: embeddingModel,
            embeddingDimensions: dimensions,
            sttModel: sttModel,
            visionModel: visionModel
        )
    }

    // MARK: - Local Provider Builders

    private func buildLocalTextGenProvider() -> any TextGenerationProvider {
        let engine = textGenerationEngine as? TextGenerationCapable
            ?? TextGenerationCapableAdapter(engine: textGenerationEngine)
        return LocalTextGenerationProvider(engine: engine)
    }

    private func buildLocalEmbeddingProvider() -> any EmbeddingProvider {
        let engine = embeddingEngine as? EmbeddingCapable
            ?? EmbeddingCapableAdapter(engine: embeddingEngine)
        return LocalEmbeddingProvider(engine: engine, dimensions: embeddingEngine.embeddingDimension)
    }

    private func buildLocalSTTProvider() -> any STTProvider {
        let engine = transcriptionEngine as? TranscriptionCapable
            ?? TranscriptionCapableAdapter(engine: transcriptionEngine)
        return LocalSTTProvider(engine: engine)
    }

    private func buildLocalVisionProvider() -> any VisionProvider {
        let engine = ocrEngine as? VisionCapable
            ?? VisionCapableAdapter(engine: ocrEngine)
        return LocalVisionProvider(engine: engine)
    }

    private func buildLocalTTSProvider(engine: any TTSEngineProtocol) -> any TTSProvider {
        return LocalTTSProvider(engine: engine)
    }
}

// MARK: - Adapters for Protocol Bridging

/// Adapts a bare TranscriptionEngineProtocol to TranscriptionCapable
private final class TranscriptionCapableAdapter: TranscriptionCapable, @unchecked Sendable {
    private let _engine: any TranscriptionEngineProtocol

    var isLoaded: Bool { _engine.isLoaded }
    func load() async throws { try await _engine.load() }
    func unload() { _engine.unload() }

    init(engine: any TranscriptionEngineProtocol) {
        _engine = engine
    }

    func transcribe(audioArray: [Float], sampleRate: Int, language: String?) async throws -> [TranscriptionSegment] {
        return []
    }
}

/// Adapts a bare TextGenerationEngineProtocol to TextGenerationCapable
private final class TextGenerationCapableAdapter: TextGenerationCapable, @unchecked Sendable {
    private let _engine: any TextGenerationEngineProtocol

    var isLoaded: Bool { _engine.isLoaded }
    func load() async throws { try await _engine.load() }
    func unload() { _engine.unload() }

    init(engine: any TextGenerationEngineProtocol) {
        _engine = engine
    }

    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}

/// Adapts a bare EmbeddingEngineProtocol to EmbeddingCapable
private final class EmbeddingCapableAdapter: EmbeddingCapable, @unchecked Sendable {
    private let _engine: any EmbeddingEngineProtocol

    var isLoaded: Bool { _engine.isLoaded }
    var embeddingDimension: Int { _engine.embeddingDimension }
    func load() async throws { try await _engine.load() }
    func unload() { _engine.unload() }

    init(engine: any EmbeddingEngineProtocol) {
        _engine = engine
    }

    func embed(text: String, mode: EmbeddingMode) async throws -> [Float] {
        return []
    }

    func embedBatch(texts: [String], mode: EmbeddingMode) async throws -> [[Float]] {
        return []
    }
}

/// Adapts a bare OCREngineActorProtocol to VisionCapable
private actor VisionCapableAdapter: VisionCapable {
    private let _engine: any OCREngineActorProtocol

    nonisolated var isLoaded: Bool {
        get async { await _engine.isLoaded }
    }

    func load() async throws { try await _engine.load() }
    func unload() async { await _engine.unload() }

    init(engine: any OCREngineActorProtocol) {
        _engine = engine
    }

    func extractText(from image: CIImage) async throws -> String {
        return ""
    }
}
