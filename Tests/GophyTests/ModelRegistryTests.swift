import XCTest
@testable import Gophy

final class ModelRegistryTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var modelRegistry: ModelRegistry!

    override func setUp() async throws {
        try await super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        storageManager = StorageManager(baseDirectory: tempDirectory)
        modelRegistry = ModelRegistry(storageManager: storageManager)
    }

    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try await super.tearDown()
    }

    func testAvailableModelsReturnsExactlyFourModels() throws {
        let models = modelRegistry.availableModels()
        XCTAssertEqual(models.count, 4, "ModelRegistry should return exactly 4 models")
    }

    func testEachModelHasCorrectType() throws {
        let models = modelRegistry.availableModels()

        let sttModels = models.filter { $0.type == .stt }
        XCTAssertEqual(sttModels.count, 1, "Should have exactly 1 STT model")

        let textGenModels = models.filter { $0.type == .textGen }
        XCTAssertEqual(textGenModels.count, 1, "Should have exactly 1 TextGen model")

        let ocrModels = models.filter { $0.type == .ocr }
        XCTAssertEqual(ocrModels.count, 1, "Should have exactly 1 OCR model")

        let embeddingModels = models.filter { $0.type == .embedding }
        XCTAssertEqual(embeddingModels.count, 1, "Should have exactly 1 Embedding model")
    }

    func testIsDownloadedReturnsFalseForModelsNotOnDisk() throws {
        let models = modelRegistry.availableModels()

        for model in models {
            XCTAssertFalse(
                modelRegistry.isDownloaded(model),
                "Model \(model.name) should not be marked as downloaded when not on disk"
            )
        }
    }

    func testDownloadPathReturnsCorrectPathUnderModelsDirectory() throws {
        let models = modelRegistry.availableModels()
        let modelsDirectory = storageManager.modelsDirectory

        for model in models {
            let downloadPath = modelRegistry.downloadPath(for: model)

            XCTAssertTrue(
                downloadPath.path.hasPrefix(modelsDirectory.path),
                "Download path for \(model.name) should be under models directory"
            )

            XCTAssertTrue(
                downloadPath.path.contains(model.id),
                "Download path for \(model.name) should contain model ID"
            )
        }
    }

    func testIsDownloadedReturnsTrueWhenModelDirectoryExistsWithFiles() throws {
        let models = modelRegistry.availableModels()
        guard let firstModel = models.first else {
            XCTFail("No models available")
            return
        }

        let downloadPath = modelRegistry.downloadPath(for: firstModel)
        try FileManager.default.createDirectory(at: downloadPath, withIntermediateDirectories: true)

        let configFile = downloadPath.appendingPathComponent("config.json")
        try "{}".write(to: configFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(
            modelRegistry.isDownloaded(firstModel),
            "Model should be marked as downloaded when directory exists with files"
        )
    }

    func testIsDownloadedReturnsFalseWhenModelDirectoryExistsButIsEmpty() throws {
        let models = modelRegistry.availableModels()
        guard let firstModel = models.first else {
            XCTFail("No models available")
            return
        }

        let downloadPath = modelRegistry.downloadPath(for: firstModel)
        try FileManager.default.createDirectory(at: downloadPath, withIntermediateDirectories: true)

        XCTAssertFalse(
            modelRegistry.isDownloaded(firstModel),
            "Model should not be marked as downloaded when directory is empty"
        )
    }

    func testModelDefinitionsHaveCorrectHuggingFaceIDs() throws {
        let models = modelRegistry.availableModels()

        let sttModel = models.first { $0.type == .stt }
        XCTAssertEqual(sttModel?.huggingFaceID, "argmaxinc/whisperkit-coreml-large-v3-turbo")

        let textGenModel = models.first { $0.type == .textGen }
        XCTAssertEqual(textGenModel?.huggingFaceID, "mlx-community/Qwen2.5-7B-Instruct-4bit")

        let ocrModel = models.first { $0.type == .ocr }
        XCTAssertEqual(ocrModel?.huggingFaceID, "mlx-community/Qwen2.5-VL-7B-Instruct-4bit")

        let embeddingModel = models.first { $0.type == .embedding }
        XCTAssertEqual(embeddingModel?.huggingFaceID, "nomic-ai/nomic-embed-text-v1.5")
    }

    func testModelDefinitionsHaveCorrectMemorySizes() throws {
        let models = modelRegistry.availableModels()

        guard let sttModel = models.first(where: { $0.type == .stt }) else {
            XCTFail("STT model not found")
            return
        }
        XCTAssertEqual(sttModel.approximateSizeGB, 1.5, accuracy: 0.1)
        XCTAssertEqual(sttModel.memoryUsageGB, 1.5, accuracy: 0.1)

        guard let textGenModel = models.first(where: { $0.type == .textGen }) else {
            XCTFail("TextGen model not found")
            return
        }
        XCTAssertEqual(textGenModel.approximateSizeGB, 4.0, accuracy: 0.1)
        XCTAssertEqual(textGenModel.memoryUsageGB, 4.0, accuracy: 0.1)

        guard let ocrModel = models.first(where: { $0.type == .ocr }) else {
            XCTFail("OCR model not found")
            return
        }
        XCTAssertEqual(ocrModel.approximateSizeGB, 4.0, accuracy: 0.1)
        XCTAssertEqual(ocrModel.memoryUsageGB, 4.0, accuracy: 0.1)

        guard let embeddingModel = models.first(where: { $0.type == .embedding }) else {
            XCTFail("Embedding model not found")
            return
        }
        XCTAssertEqual(embeddingModel.approximateSizeGB, 0.3, accuracy: 0.1)
        XCTAssertEqual(embeddingModel.memoryUsageGB, 0.3, accuracy: 0.1)
    }

    func testModelDefinitionsHaveDisplayNames() throws {
        let models = modelRegistry.availableModels()

        for model in models {
            XCTAssertFalse(model.name.isEmpty, "Model \(model.id) should have a display name")
            XCTAssertFalse(model.id.isEmpty, "Model should have an ID")
        }

        let sttModel = models.first { $0.type == .stt }
        XCTAssertEqual(sttModel?.name, "WhisperKit large-v3-turbo")

        let textGenModel = models.first { $0.type == .textGen }
        XCTAssertEqual(textGenModel?.name, "Qwen2.5 7B Instruct 4-bit")

        let ocrModel = models.first { $0.type == .ocr }
        XCTAssertEqual(ocrModel?.name, "Qwen2.5-VL 7B Instruct 4-bit")

        let embeddingModel = models.first { $0.type == .embedding }
        XCTAssertEqual(embeddingModel?.name, "nomic-embed-text v1.5")
    }

    func testModelDefinitionsAreUnique() throws {
        let models = modelRegistry.availableModels()
        let ids = models.map { $0.id }
        let uniqueIds = Set(ids)

        XCTAssertEqual(
            ids.count,
            uniqueIds.count,
            "All model IDs should be unique"
        )
    }
}
