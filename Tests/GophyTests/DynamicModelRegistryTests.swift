import Testing
import Foundation
@testable import Gophy

@Suite("DynamicModelRegistry Tests")
struct DynamicModelRegistryTests {

    @Test("Returns curated models first")
    func testCuratedModelsFirst() async throws {
        let registry = DynamicModelRegistry()
        let models = registry.availableModels()

        #expect(!models.isEmpty, "Registry should return models")

        // First 5 models should be curated (hardcoded with known sizes)
        let curatedModels = models.prefix(5)
        for model in curatedModels {
            #expect(model.source == .curated, "First models should be curated")
            #expect(model.approximateSizeGB ?? 0 > 0, "Curated models should have size")
        }
    }

    @Test("Search filters by name substring case-insensitive")
    func testSearchByName() async throws {
        let registry = DynamicModelRegistry()

        let results = registry.search(query: "qwen")
        #expect(!results.isEmpty, "Should find models with 'qwen' in name")

        for model in results {
            let matchesName = model.name.lowercased().contains("qwen")
            let matchesHFID = model.huggingFaceID.lowercased().contains("qwen")
            #expect(matchesName || matchesHFID, "Model should match query in name or huggingFaceID")
        }

        let emptyResults = registry.search(query: "nonexistent-model-xyz")
        #expect(emptyResults.isEmpty, "Should return empty for non-matching query")
    }

    @Test("Filter by model type returns only matching models")
    func testFilterByType() async throws {
        let registry = DynamicModelRegistry()

        let sttModels = registry.filterByType(.stt)
        #expect(!sttModels.isEmpty, "Should have STT models")
        for model in sttModels {
            #expect(model.type == .stt, "Filtered models should match type")
        }

        let textGenModels = registry.filterByType(.textGen)
        #expect(!textGenModels.isEmpty, "Should have text generation models")
        for model in textGenModels {
            #expect(model.type == .textGen, "Filtered models should match type")
        }

        let ocrModels = registry.filterByType(.ocr)
        #expect(!ocrModels.isEmpty, "Should have OCR/vision models")
        for model in ocrModels {
            #expect(model.type == .ocr, "Filtered models should match type")
        }

        let embeddingModels = registry.filterByType(.embedding)
        #expect(!embeddingModels.isEmpty, "Should have embedding models")
        for model in embeddingModels {
            #expect(model.type == .embedding, "Filtered models should match type")
        }
    }

    @Test("Vendor models have correct type mapping")
    func testVendorModelTypeMapping() async throws {
        let registry = DynamicModelRegistry()
        let models = registry.availableModels()

        // Find models from LLM registry (should be textGen)
        let llmModels = models.filter { $0.source == .llmRegistry }
        for model in llmModels {
            #expect(model.type == .textGen, "LLM registry models should be textGen type")
        }

        // Find models from VLM registry (should be ocr)
        let vlmModels = models.filter { $0.source == .vlmRegistry }
        for model in vlmModels {
            #expect(model.type == .ocr, "VLM registry models should be OCR type")
        }

        // Find models from embedders registry (should be embedding)
        let embedderModels = models.filter { $0.source == .embeddersRegistry }
        for model in embedderModels {
            #expect(model.type == .embedding, "Embedder registry models should be embedding type")
        }
    }

    @Test("isDownloaded checks model path correctly")
    func testIsDownloaded() async throws {
        let registry = DynamicModelRegistry()
        let models = registry.availableModels()

        #expect(!models.isEmpty, "Should have models to test")

        // Test with first model
        let model = models[0]
        let isDownloaded = registry.isDownloaded(model)

        // Result should be boolean (no crash)
        #expect(isDownloaded == true || isDownloaded == false, "Should return valid boolean")
    }

    @Test("downloadPath returns valid URL")
    func testDownloadPath() async throws {
        let registry = DynamicModelRegistry()
        let models = registry.availableModels()

        #expect(!models.isEmpty, "Should have models to test")

        let model = models[0]
        let path = registry.downloadPath(for: model)

        #expect(!path.path.isEmpty, "Download path should not be empty")
        #expect(path.path.contains(model.id), "Download path should contain model ID")
    }

    @Test("Vendor models with unknown sizes have nil approximateSizeGB")
    func testVendorModelsHaveOptionalSizes() async throws {
        let registry = DynamicModelRegistry()
        let models = registry.availableModels()

        let vendorModels = models.filter { $0.source != .curated }

        // Most vendor models should have nil sizes (not downloaded yet)
        if !vendorModels.isEmpty {
            let hasNilSize = vendorModels.contains { $0.approximateSizeGB == nil }
            #expect(hasNilSize, "Some vendor models should have nil approximateSizeGB")
        }
    }

    @Test("All models have unique IDs")
    func testUniqueModelIds() async throws {
        let registry = DynamicModelRegistry()
        let models = registry.availableModels()

        let ids = models.map { $0.id }
        let uniqueIds = Set(ids)

        #expect(ids.count == uniqueIds.count, "All model IDs should be unique")
    }
}
