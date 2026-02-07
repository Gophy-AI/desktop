import Testing
import Foundation
@testable import Gophy

@Suite("ProviderRegistry Tests")
struct ProviderRegistryTests {

    // MARK: - Helpers

    private func makeRegistry(
        keychainService: MockKeychainForRegistry = MockKeychainForRegistry(),
        userDefaults: UserDefaults? = nil,
        transcriptionEngine: any TranscriptionEngineProtocol = StubTranscriptionEngineForRegistry(),
        textGenerationEngine: any TextGenerationEngineProtocol = StubTextGenerationEngineForRegistry(),
        embeddingEngine: any EmbeddingEngineProtocol = StubEmbeddingEngineForRegistry(),
        ocrEngine: any OCREngineActorProtocol = StubOCREngineForRegistry()
    ) -> ProviderRegistry {
        let defaults = userDefaults ?? {
            let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
            d.removePersistentDomain(forName: d.volatileDomainNames.first ?? "")
            return d
        }()

        return ProviderRegistry(
            keychainService: keychainService,
            userDefaults: defaults,
            transcriptionEngine: transcriptionEngine,
            textGenerationEngine: textGenerationEngine,
            embeddingEngine: embeddingEngine,
            ocrEngine: ocrEngine
        )
    }

    // MARK: - Default Provider Tests

    @Test("Default returns local providers for all capabilities")
    func testDefaultReturnsLocalProviders() async throws {
        let registry = makeRegistry()

        let textGen = registry.activeTextGenProvider()
        let embedding = registry.activeEmbeddingProvider()
        let stt = registry.activeSTTProvider()
        let vision = registry.activeVisionProvider()

        #expect(textGen is LocalTextGenerationProvider)
        #expect(embedding is LocalEmbeddingProvider)
        #expect(stt is LocalSTTProvider)
        #expect(vision is LocalVisionProvider)
    }

    // MARK: - Cloud Provider Configuration

    @Test("Configuring OpenAI provider with API key returns cloud provider for textGen")
    func testConfigureOpenAIReturnsCloudProvider() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        try registry.configureProvider(id: "openai", apiKey: "sk-test-key")
        registry.selectProvider(for: .textGeneration, providerId: "openai", modelId: "gpt-4o")

        let textGen = registry.activeTextGenProvider()
        #expect(textGen is OpenAICompatibleProvider)
    }

    @Test("Configuring Anthropic provider returns AnthropicProvider for textGen")
    func testConfigureAnthropicReturnsAnthropicProvider() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        try registry.configureProvider(id: "anthropic", apiKey: "sk-ant-test")
        registry.selectProvider(for: .textGeneration, providerId: "anthropic", modelId: "claude-sonnet-4-5-20250929")

        let textGen = registry.activeTextGenProvider()
        #expect(textGen is AnthropicProvider)
    }

    // MARK: - Persistence

    @Test("Provider selection persists via UserDefaults")
    func testSelectionPersistsAcrossInstances() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!

        let registry1 = makeRegistry(keychainService: keychain, userDefaults: defaults)
        try registry1.configureProvider(id: "openai", apiKey: "sk-test")
        registry1.selectProvider(for: .textGeneration, providerId: "openai", modelId: "gpt-4o")

        let registry2 = makeRegistry(keychainService: keychain, userDefaults: defaults)
        let textGen = registry2.activeTextGenProvider()
        #expect(textGen is OpenAICompatibleProvider)
    }

    // MARK: - Remove Provider

    @Test("Removing API key reverts to local provider")
    func testRemoveProviderRevertsToLocal() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        try registry.configureProvider(id: "openai", apiKey: "sk-test")
        registry.selectProvider(for: .textGeneration, providerId: "openai", modelId: "gpt-4o")
        #expect(registry.activeTextGenProvider() is OpenAICompatibleProvider)

        try registry.removeProvider(id: "openai")

        let textGen = registry.activeTextGenProvider()
        #expect(textGen is LocalTextGenerationProvider)
    }

    // MARK: - Configured Providers

    @Test("configuredProviders returns IDs with stored API keys")
    func testConfiguredProviders() async throws {
        let keychain = MockKeychainForRegistry()
        let registry = makeRegistry(keychainService: keychain)

        try registry.configureProvider(id: "openai", apiKey: "sk-1")
        try registry.configureProvider(id: "groq", apiKey: "gsk-1")

        let configured = registry.configuredProviders()
        #expect(configured.contains("openai"))
        #expect(configured.contains("groq"))
        #expect(!configured.contains("anthropic"))
    }

    // MARK: - Provider Switch Notification

    @Test("Provider switch emits change notification via providerChangeStream")
    func testProviderSwitchEmitsNotification() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        try registry.configureProvider(id: "openai", apiKey: "sk-test")

        var receivedCapabilities: [ProviderCapability] = []
        let collectTask = Task {
            for await capability in registry.providerChangeStream {
                receivedCapabilities.append(capability)
                if receivedCapabilities.count >= 1 {
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        registry.selectProvider(for: .textGeneration, providerId: "openai", modelId: "gpt-4o")

        try await Task.sleep(for: .milliseconds(100))
        collectTask.cancel()

        #expect(receivedCapabilities.contains(.textGeneration))
    }

    // MARK: - Per-Capability Selection

    @Test("activeEmbeddingProvider returns configured cloud provider")
    func testActiveEmbeddingProvider() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        try registry.configureProvider(id: "openai", apiKey: "sk-test")
        registry.selectProvider(for: .embedding, providerId: "openai", modelId: "text-embedding-3-small")

        let embedding = registry.activeEmbeddingProvider()
        #expect(embedding is OpenAICompatibleProvider)
    }

    @Test("activeSTTProvider returns configured cloud provider")
    func testActiveSTTProvider() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        try registry.configureProvider(id: "openai", apiKey: "sk-test")
        registry.selectProvider(for: .speechToText, providerId: "openai", modelId: "whisper-1")

        let stt = registry.activeSTTProvider()
        #expect(stt is OpenAICompatibleProvider)
    }

    @Test("activeVisionProvider returns configured cloud provider")
    func testActiveVisionProvider() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        try registry.configureProvider(id: "anthropic", apiKey: "sk-ant-test")
        registry.selectProvider(for: .vision, providerId: "anthropic", modelId: "claude-sonnet-4-5-20250929")

        let vision = registry.activeVisionProvider()
        #expect(vision is AnthropicProvider)
    }

    @Test("Selected provider ID for capability is returned correctly")
    func testSelectedProviderIdForCapability() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        #expect(registry.selectedProviderId(for: .textGeneration) == "local")

        try registry.configureProvider(id: "openai", apiKey: "sk-test")
        registry.selectProvider(for: .textGeneration, providerId: "openai", modelId: "gpt-4o")

        #expect(registry.selectedProviderId(for: .textGeneration) == "openai")
    }

    @Test("isCloudProvider returns true for non-local providers")
    func testIsCloudProvider() async throws {
        let keychain = MockKeychainForRegistry()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let registry = makeRegistry(keychainService: keychain, userDefaults: defaults)

        #expect(!registry.isCloudProvider(for: .textGeneration))

        try registry.configureProvider(id: "openai", apiKey: "sk-test")
        registry.selectProvider(for: .textGeneration, providerId: "openai", modelId: "gpt-4o")

        #expect(registry.isCloudProvider(for: .textGeneration))
    }
}

// MARK: - Mocks

final class MockKeychainForRegistry: KeychainServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _store: [String: String] = [:]

    func save(apiKey: String, for providerId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        _store[providerId] = apiKey
    }

    func retrieve(for providerId: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return _store[providerId]
    }

    func delete(for providerId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        _store.removeValue(forKey: providerId)
    }

    func listProviderIds() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_store.keys)
    }
}

final class StubTranscriptionEngineForRegistry: TranscriptionEngineProtocol, @unchecked Sendable {
    var isLoaded: Bool = false
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

final class StubTextGenerationEngineForRegistry: TextGenerationEngineProtocol, @unchecked Sendable {
    var isLoaded: Bool = false
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

final class StubEmbeddingEngineForRegistry: EmbeddingEngineProtocol, @unchecked Sendable {
    var isLoaded: Bool = false
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

actor StubOCREngineForRegistry: OCREngineActorProtocol {
    private var _isLoaded = false

    nonisolated var isLoaded: Bool {
        get async { await getIsLoaded() }
    }

    private func getIsLoaded() -> Bool { _isLoaded }

    func load() async throws { _isLoaded = true }
    func unload() async { _isLoaded = false }
}
