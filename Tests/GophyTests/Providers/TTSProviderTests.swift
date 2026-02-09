import Testing
import Foundation
@testable import Gophy

@Suite("TTSProvider Tests")
struct TTSProviderTests {

    // MARK: - Mock TTSEngine

    final class MockTTSEngineForProvider: TTSEngineProtocol, @unchecked Sendable {
        var isLoaded: Bool = true
        var synthesizeCalled = false
        var lastSynthesizedText: String?
        var lastSynthesizedVoice: String?
        var stubSamples: [Float] = Array(repeating: 0.5, count: 22050)
        var shouldThrow = false

        func load() async throws {
            isLoaded = true
        }

        func synthesize(text: String, voice: String?) async throws -> [Float] {
            if shouldThrow {
                throw TTSError.modelNotLoaded
            }
            synthesizeCalled = true
            lastSynthesizedText = text
            lastSynthesizedVoice = voice
            return stubSamples
        }

        func synthesizeStream(text: String, voice: String?) -> AsyncThrowingStream<[Float], Error> {
            let samples = stubSamples
            let throwError = shouldThrow
            return AsyncThrowingStream { continuation in
                if throwError {
                    continuation.finish(throwing: TTSError.modelNotLoaded)
                    return
                }
                // Yield two chunks
                let half = samples.count / 2
                continuation.yield(Array(samples[0..<half]))
                continuation.yield(Array(samples[half...]))
                continuation.finish()
            }
        }

        func unload() {
            isLoaded = false
        }
    }

    // MARK: - Test 1: TTSProvider protocol conformance

    @Test("LocalTTSProvider conforms to TTSProvider protocol")
    func testLocalTTSProviderConformance() {
        let engine = MockTTSEngineForProvider()
        let provider: any TTSProvider = LocalTTSProvider(engine: engine, sampleRate: 22050)
        #expect(provider.sampleRate == 22050)
    }

    // MARK: - Test 2: LocalTTSProvider delegates to TTSEngine

    @Test("LocalTTSProvider.synthesize delegates to TTSEngine")
    func testSynthesizeDelegatesToEngine() async throws {
        let engine = MockTTSEngineForProvider()
        let provider = LocalTTSProvider(engine: engine, sampleRate: 22050)

        _ = try await provider.synthesize(text: "Hello world", voice: "default")

        #expect(engine.synthesizeCalled)
        #expect(engine.lastSynthesizedText == "Hello world")
        #expect(engine.lastSynthesizedVoice == "default")
    }

    // MARK: - Test 3: LocalTTSProvider returns audio Data in WAV format

    @Test("LocalTTSProvider.synthesize returns valid WAV data")
    func testSynthesizeReturnsWAVData() async throws {
        let engine = MockTTSEngineForProvider()
        engine.stubSamples = [0.0, 0.5, -0.5, 1.0]
        let provider = LocalTTSProvider(engine: engine, sampleRate: 22050)

        let wavData = try await provider.synthesize(text: "Test", voice: nil)

        // WAV header is 44 bytes
        #expect(wavData.count > 44)

        // Check RIFF header
        let riffHeader = String(data: wavData[0..<4], encoding: .ascii)
        #expect(riffHeader == "RIFF")

        // Check WAVE format
        let waveFormat = String(data: wavData[8..<12], encoding: .ascii)
        #expect(waveFormat == "WAVE")

        // Check fmt chunk
        let fmtChunk = String(data: wavData[12..<16], encoding: .ascii)
        #expect(fmtChunk == "fmt ")

        // Audio format should be 1 (PCM)
        let audioFormat = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 20, as: UInt16.self)
        }
        #expect(audioFormat == 1)

        // Sample rate should be 22050
        let sampleRate = wavData.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: 24, as: UInt32.self)
        }
        #expect(sampleRate == 22050)

        // Data size: 4 Float samples * 2 bytes per Int16 sample = 8 bytes
        let dataSize = wavData.count - 44
        #expect(dataSize == 8)
    }

    // MARK: - Test 4: ProviderCapability.textToSpeech case exists

    @Test("ProviderCapability has textToSpeech case")
    func testProviderCapabilityTextToSpeechExists() {
        let capability = ProviderCapability.textToSpeech
        #expect(capability.rawValue == "textToSpeech")
        #expect(ProviderCapability.allCases.contains(.textToSpeech))
    }

    // MARK: - Test 5: ProviderRegistry.activeTTSProvider() returns local provider

    @Test("ProviderRegistry.activeTTSProvider returns LocalTTSProvider by default")
    func testRegistryReturnsTTSProvider() {
        let defaults = UserDefaults(suiteName: "tts-test-\(UUID().uuidString)")!
        let registry = ProviderRegistry(
            keychainService: MockKeychainForTTSTest(),
            userDefaults: defaults,
            transcriptionEngine: StubTranscriptionEngineForTTS(),
            textGenerationEngine: StubTextGenerationEngineForTTS(),
            embeddingEngine: StubEmbeddingEngineForTTS(),
            ocrEngine: StubOCREngineForTTS(),
            ttsEngine: MockTTSEngineForProvider()
        )

        let ttsProvider = registry.activeTTSProvider()
        #expect(ttsProvider != nil)
        #expect(ttsProvider is LocalTTSProvider)
    }

    // MARK: - Test 6: synthesizeStream returns WAV chunks

    @Test("LocalTTSProvider.synthesizeStream yields Data chunks")
    func testSynthesizeStreamYieldsChunks() async throws {
        let engine = MockTTSEngineForProvider()
        engine.stubSamples = Array(repeating: 0.5, count: 100)
        let provider = LocalTTSProvider(engine: engine, sampleRate: 22050)

        var chunks: [Data] = []
        let stream = provider.synthesizeStream(text: "Stream test", voice: nil)
        for try await chunk in stream {
            chunks.append(chunk)
        }

        #expect(chunks.count == 2)
        for chunk in chunks {
            #expect(!chunk.isEmpty)
        }
    }

    // MARK: - Test 7: synthesize propagates engine errors

    @Test("LocalTTSProvider.synthesize propagates engine errors")
    func testSynthesizePropagatesErrors() async {
        let engine = MockTTSEngineForProvider()
        engine.shouldThrow = true
        let provider = LocalTTSProvider(engine: engine, sampleRate: 22050)

        do {
            _ = try await provider.synthesize(text: "Fail", voice: nil)
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is TTSError)
        }
    }

    // MARK: - Test 8: sampleRate is correctly returned

    @Test("LocalTTSProvider exposes correct sampleRate")
    func testSampleRateExposed() {
        let engine = MockTTSEngineForProvider()
        let provider24k = LocalTTSProvider(engine: engine, sampleRate: 24000)
        #expect(provider24k.sampleRate == 24000)

        let provider22k = LocalTTSProvider(engine: engine, sampleRate: 22050)
        #expect(provider22k.sampleRate == 22050)
    }
}

// MARK: - Test Stubs for ProviderRegistry

private final class MockKeychainForTTSTest: KeychainServiceProtocol, @unchecked Sendable {
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

private final class StubTranscriptionEngineForTTS: TranscriptionEngineProtocol, @unchecked Sendable {
    var isLoaded: Bool = false
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

private final class StubTextGenerationEngineForTTS: TextGenerationEngineProtocol, @unchecked Sendable {
    var isLoaded: Bool = false
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

private final class StubEmbeddingEngineForTTS: EmbeddingEngineProtocol, @unchecked Sendable {
    var isLoaded: Bool = false
    var embeddingDimension: Int = 384
    func load() async throws { isLoaded = true }
    func unload() { isLoaded = false }
}

private actor StubOCREngineForTTS: OCREngineActorProtocol {
    private var _isLoaded = false

    nonisolated var isLoaded: Bool {
        get async { await getIsLoaded() }
    }

    private func getIsLoaded() -> Bool { _isLoaded }

    func load() async throws { _isLoaded = true }
    func unload() async { _isLoaded = false }
}
