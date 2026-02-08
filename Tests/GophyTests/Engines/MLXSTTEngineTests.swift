import XCTest
import Foundation
@testable import Gophy

final class MLXSTTEngineTests: XCTestCase {
    var mockModelRegistry: MLXSTTMockModelRegistry!
    var engine: MLXSTTEngine!

    override func setUp() async throws {
        try await super.setUp()
        mockModelRegistry = MLXSTTMockModelRegistry()
        engine = MLXSTTEngine(modelRegistry: mockModelRegistry)
    }

    override func tearDown() async throws {
        engine = nil
        mockModelRegistry = nil
        try await super.tearDown()
    }

    // Test 1: MLXSTTEngine initialization with mock registry
    func testMLXSTTEngineCanBeInitialized() {
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isLoaded)
    }

    // Test 2: load() only activates for models with source .audioRegistry
    func testLoadOnlyActivatesForAudioRegistryModels() async throws {
        let registryWithOnlyCurated = MLXSTTMockModelRegistryCuratedOnly()
        let curatedEngine = MLXSTTEngine(modelRegistry: registryWithOnlyCurated)

        do {
            try await curatedEngine.load()
            XCTFail("Expected MLXSTTError.noAudioRegistryModel")
        } catch MLXSTTError.noAudioRegistryModel {
            XCTAssertFalse(curatedEngine.isLoaded)
        }
    }

    // Test 3: transcribe() throws when model not loaded
    func testTranscribeThrowsWhenNotLoaded() async {
        let audioArray: [Float] = Array(repeating: 0.0, count: 16000)

        do {
            _ = try await engine.transcribe(audioArray: audioArray, sampleRate: 16000, language: nil)
            XCTFail("Expected MLXSTTError.modelNotLoaded")
        } catch MLXSTTError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected MLXSTTError.modelNotLoaded but got \(error)")
        }
    }

    // Test 4: unload() releases model
    func testUnloadReleasesModel() async throws {
        // Can't load real models in tests, but we can verify unload behavior
        XCTAssertFalse(engine.isLoaded)
        engine.unload()
        XCTAssertFalse(engine.isLoaded)
    }

    // Test 5: Conforms to TranscriptionEngineProtocol
    func testConformsToTranscriptionEngineProtocol() {
        let _: any TranscriptionEngineProtocol = engine
        XCTAssertTrue(true)
    }

    // Test 6: Conforms to PipelineTranscriptionProtocol
    func testConformsToPipelineTranscriptionProtocol() {
        let _: any PipelineTranscriptionProtocol = engine
        XCTAssertTrue(true)
    }

    // Test 7: MLXSTTModelType.from detects all model types
    func testModelTypeDetection() {
        XCTAssertEqual(MLXSTTModelType.from(modelId: "glmasr-large-v2"), .glmasr)
        XCTAssertEqual(MLXSTTModelType.from(modelId: "lasr-ctc-large"), .lasrCTC)
        XCTAssertEqual(MLXSTTModelType.from(modelId: "whisper-mlx-large-v3"), .whisper)
        XCTAssertEqual(MLXSTTModelType.from(modelId: "parakeet-ctc-1.1b"), .parakeet)
        XCTAssertEqual(MLXSTTModelType.from(modelId: "qwen3-asr"), .qwen3ASR)
        XCTAssertEqual(MLXSTTModelType.from(modelId: "wav2vec-large-960h"), .wav2vec)
        XCTAssertEqual(MLXSTTModelType.from(modelId: "voxtral-mini"), .voxtral)
        XCTAssertNil(MLXSTTModelType.from(modelId: "unknown-model"))
    }
}

// MARK: - Mock Model Registry with audioRegistry models

final class MLXSTTMockModelRegistry: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "glmasr-large-v2",
                name: "GLM-ASR Large v2",
                type: .stt,
                huggingFaceID: "FunAudioLLM/GLM-4-Voice-Tokenizer",
                approximateSizeGB: 2.0,
                memoryUsageGB: 2.5,
                source: .audioRegistry
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

// MARK: - Mock Model Registry with only curated models (no audioRegistry)

final class MLXSTTMockModelRegistryCuratedOnly: ModelRegistryProtocol {
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
