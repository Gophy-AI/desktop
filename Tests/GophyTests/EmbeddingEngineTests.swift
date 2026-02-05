import XCTest
import Foundation
@testable import Gophy

final class EmbeddingEngineTests: XCTestCase {
    var mockModelRegistry: EmbeddingMockModelRegistry!
    var engine: EmbeddingEngine!

    override func setUp() async throws {
        try await super.setUp()
        mockModelRegistry = EmbeddingMockModelRegistry()
        engine = EmbeddingEngine(modelRegistry: mockModelRegistry)
    }

    override func tearDown() async throws {
        engine = nil
        mockModelRegistry = nil
        try await super.tearDown()
    }

    func testEmbeddingEngineCanBeInitialized() {
        XCTAssertNotNil(engine)
        XCTAssertFalse(engine.isLoaded)
    }

    func testEmbeddingEngineLoadSetsIsLoadedToTrue() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    func testEmbedThrowsWhenModelNotLoaded() async {
        do {
            _ = try await engine.embed(text: "test text")
            XCTFail("Expected EmbeddingError.modelNotLoaded")
        } catch EmbeddingError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected EmbeddingError.modelNotLoaded but got \(error)")
        }
    }

    func testEmbedBatchThrowsWhenModelNotLoaded() async {
        do {
            _ = try await engine.embedBatch(texts: ["test1", "test2"])
            XCTFail("Expected EmbeddingError.modelNotLoaded")
        } catch EmbeddingError.modelNotLoaded {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected EmbeddingError.modelNotLoaded but got \(error)")
        }
    }

    func testEmbedReturnsFloatArray() async throws {
        try await engine.load()

        let embedding = try await engine.embed(text: "Hello, world!")

        XCTAssertFalse(embedding.isEmpty)
        XCTAssertGreaterThan(embedding.count, 0)
    }

    func testEmbedBatchReturnsArrayOfFloatArrays() async throws {
        try await engine.load()

        let texts = ["Hello, world!", "How are you?"]
        let embeddings = try await engine.embedBatch(texts: texts)

        XCTAssertEqual(embeddings.count, texts.count)
        for embedding in embeddings {
            XCTAssertFalse(embedding.isEmpty)
            XCTAssertGreaterThan(embedding.count, 0)
        }
    }

    func testUnloadSetsIsLoadedToFalse() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)
    }

    func testUnloadAllowsReloading() async throws {
        try await engine.load()
        XCTAssertTrue(engine.isLoaded)

        engine.unload()
        XCTAssertFalse(engine.isLoaded)

        try await engine.load()
        XCTAssertTrue(engine.isLoaded)
    }

    func testEmbedConsistency() async throws {
        try await engine.load()

        let text = "This is a test sentence."
        let embedding1 = try await engine.embed(text: text)
        let embedding2 = try await engine.embed(text: text)

        XCTAssertEqual(embedding1.count, embedding2.count)
        for (val1, val2) in zip(embedding1, embedding2) {
            XCTAssertEqual(val1, val2, accuracy: 0.0001)
        }
    }
}

final class EmbeddingMockModelRegistry: ModelRegistryProtocol {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "nomic-embed-text-v1.5",
                name: "nomic-embed-text v1.5",
                type: .embedding,
                huggingFaceID: "nomic-ai/nomic-embed-text-v1.5",
                approximateSizeGB: 0.3,
                memoryUsageGB: 0.3
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
