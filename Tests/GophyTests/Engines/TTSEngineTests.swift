import XCTest
import Foundation
@testable import Gophy

final class TTSEngineTests: XCTestCase {
    var mockModelRegistry: TTSMockModelRegistry!
    var engine: TTSEngine!

    override func setUp() async throws {
        try await super.setUp()
        mockModelRegistry = TTSMockModelRegistry()
        engine = TTSEngine(
            modelRegistry: mockModelRegistry,
            ttsModelLoader: { _ in MockTTSModel() }
        )
    }

    override func tearDown() async throws {
        engine = nil
        mockModelRegistry = nil
        try await super.tearDown()
    }

    // Test 1: TTSEngine initialization (verify isLoaded is false initially)
    func testTTSEngineInitialIsLoadedFalse() {
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isLoaded)
    }

    // Test 2: load() selects model from UserDefaults key "selectedTTSModelId"
    func testLoadSelectsModelFromUserDefaults() async throws {
        UserDefaults.standard.set("soprano-80m-bf16", forKey: "selectedTTSModelId")
        defer { UserDefaults.standard.removeObject(forKey: "selectedTTSModelId") }

        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    // Test 3: load() falls back to first downloaded TTS model if selected not available
    func testLoadFallsBackToFirstDownloadedTTSModel() async throws {
        UserDefaults.standard.set("nonexistent-model-id", forKey: "selectedTTSModelId")
        defer { UserDefaults.standard.removeObject(forKey: "selectedTTSModelId") }

        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    // Test 4: load() throws TTSError.noModelAvailable when no TTS models exist
    func testLoadThrowsNoModelAvailableWhenNoTTSModels() async {
        let emptyRegistry = TTSMockModelRegistryEmpty()
        let emptyEngine = TTSEngine(
            modelRegistry: emptyRegistry,
            ttsModelLoader: { _ in MockTTSModel() }
        )

        do {
            try await emptyEngine.load()
            XCTFail("Expected TTSError.noModelAvailable")
        } catch TTSError.noModelAvailable {
            XCTAssertFalse(emptyEngine.isLoaded)
        } catch {
            XCTFail("Expected TTSError.noModelAvailable but got \(error)")
        }
    }

    // Test 5: synthesize(text:) throws TTSError.modelNotLoaded when not loaded
    func testSynthesizeThrowsModelNotLoadedWhenNotLoaded() async {
        do {
            _ = try await engine.synthesize(text: "Hello world", voice: nil)
            XCTFail("Expected TTSError.modelNotLoaded")
        } catch TTSError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected TTSError.modelNotLoaded but got \(error)")
        }
    }

    // Test 6: unload() sets isLoaded to false
    func testUnloadSetsIsLoadedToFalse() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)
    }

    // Test 7: TTSEngineProtocol conformance
    func testConformsToTTSEngineProtocol() {
        let _: any TTSEngineProtocol = engine
        XCTAssertTrue(true)
    }

    // Test 8: synthesize returns audio samples after loading
    func testSynthesizeReturnsAudioSamplesAfterLoading() async throws {
        try await engine.load()

        let samples = try await engine.synthesize(text: "Hello world", voice: nil)
        XCTAssertFalse(samples.isEmpty)
    }

    // Test 9: unload allows reloading
    func testUnloadAllowsReloading() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)

        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    // Test 10: load() with only non-downloaded models throws noModelAvailable
    func testLoadThrowsWhenNoDownloadedTTSModels() async {
        let notDownloadedRegistry = TTSMockModelRegistryNotDownloaded()
        let notDownloadedEngine = TTSEngine(
            modelRegistry: notDownloadedRegistry,
            ttsModelLoader: { _ in MockTTSModel() }
        )

        do {
            try await notDownloadedEngine.load()
            XCTFail("Expected TTSError.noModelAvailable")
        } catch TTSError.noModelAvailable {
            XCTAssertFalse(notDownloadedEngine.isLoaded)
        } catch {
            XCTFail("Expected TTSError.noModelAvailable but got \(error)")
        }
    }
}

// MARK: - Mock TTS Model

final class MockTTSModel: TTSModelProtocol, @unchecked Sendable {
    let sampleRate: Int = 22050

    func generate(text: String, voice: String?) async throws -> [Float] {
        return Array(repeating: 0.5, count: sampleRate)
    }
}

// MARK: - Mock Model Registry with TTS models

final class TTSMockModelRegistry: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "soprano-80m-bf16",
                name: "Soprano 80M",
                type: .tts,
                huggingFaceID: "mlx-community/Soprano-80M-bf16",
                approximateSizeGB: 0.3,
                memoryUsageGB: 0.4,
                source: .curated
            ),
            ModelDefinition(
                id: "orpheus-3b-bf16",
                name: "Orpheus 3B",
                type: .tts,
                huggingFaceID: "mlx-community/orpheus-3b-0.1-ft-bf16",
                approximateSizeGB: 6.0,
                memoryUsageGB: 6.5,
                source: .curated
            ),
            ModelDefinition(
                id: "whisperkit-large-v3-turbo",
                name: "WhisperKit large-v3-turbo",
                type: .stt,
                huggingFaceID: "argmaxinc/whisperkit-coreml-large-v3-turbo",
                approximateSizeGB: 1.5,
                memoryUsageGB: 1.5,
                source: .curated
            )
        ]
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        URL(fileURLWithPath: "/tmp/test-models/\(model.id)")
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return true
    }
}

// MARK: - Mock Model Registry with no TTS models

final class TTSMockModelRegistryEmpty: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "whisperkit-large-v3-turbo",
                name: "WhisperKit large-v3-turbo",
                type: .stt,
                huggingFaceID: "argmaxinc/whisperkit-coreml-large-v3-turbo",
                approximateSizeGB: 1.5,
                memoryUsageGB: 1.5,
                source: .curated
            )
        ]
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        URL(fileURLWithPath: "/tmp/test-models/\(model.id)")
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return true
    }
}

// MARK: - Mock Model Registry with TTS models that are not downloaded

final class TTSMockModelRegistryNotDownloaded: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "soprano-80m-bf16",
                name: "Soprano 80M",
                type: .tts,
                huggingFaceID: "mlx-community/Soprano-80M-bf16",
                approximateSizeGB: 0.3,
                memoryUsageGB: 0.4,
                source: .curated
            )
        ]
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        URL(fileURLWithPath: "/tmp/test-models/\(model.id)")
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return false
    }
}
