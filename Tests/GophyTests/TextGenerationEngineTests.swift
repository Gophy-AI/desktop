import XCTest
@testable import Gophy

final class TextGenerationEngineTests: XCTestCase {
    var engine: TextGenerationEngine!
    var mockModelRegistry: TextGenMockModelRegistry!

    override func setUp() {
        super.setUp()
        mockModelRegistry = TextGenMockModelRegistry()
        engine = TextGenerationEngine(modelRegistry: mockModelRegistry)
    }

    override func tearDown() {
        engine = nil
        mockModelRegistry = nil
        super.tearDown()
    }

    func testEngineInitializesCorrectly() {
        XCTAssertFalse(engine.isLoaded, "Engine should not be loaded initially")
    }

    func testUnloadSetsIsLoadedToFalse() async throws {
        let textGenModel = mockModelRegistry.availableModels().first { $0.type == .textGen }!
        let modelPath = mockModelRegistry.downloadPath(for: textGenModel)

        try createMockModelFiles(at: modelPath)

        try await engine.load()
        XCTAssertTrue(engine.isLoaded, "Engine should be loaded after load()")

        engine.unload()
        XCTAssertFalse(engine.isLoaded, "Engine should not be loaded after unload()")
    }

    func testGenerateWhenModelNotLoaded() async throws {
        var generatedText = ""

        for await chunk in engine.generate(prompt: "Hello") {
            generatedText += chunk
        }

        XCTAssertTrue(generatedText.isEmpty, "Generate should produce no output when model not loaded")
    }

    func testStateTransitions() async throws {
        XCTAssertFalse(engine.isLoaded, "Initial state: not loaded")

        let textGenModel = mockModelRegistry.availableModels().first { $0.type == .textGen }!
        let modelPath = mockModelRegistry.downloadPath(for: textGenModel)

        try createMockModelFiles(at: modelPath)

        try await engine.load()
        XCTAssertTrue(engine.isLoaded, "State after load: loaded")

        engine.unload()
        XCTAssertFalse(engine.isLoaded, "State after unload: not loaded")
    }

    private func createMockModelFiles(at path: URL) throws {
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)

        let configPath = path.appendingPathComponent("config.json")
        let configJSON = """
        {
            "model_type": "qwen2",
            "hidden_size": 3584,
            "intermediate_size": 18944,
            "num_attention_heads": 28,
            "num_hidden_layers": 28,
            "num_key_value_heads": 4,
            "vocab_size": 151936,
            "rope_theta": 1000000.0,
            "rope_traditional": false,
            "rms_norm_eps": 1e-06
        }
        """
        try configJSON.write(to: configPath, atomically: true, encoding: .utf8)

        let tokenizerConfigPath = path.appendingPathComponent("tokenizer_config.json")
        let tokenizerConfigJSON = """
        {
            "add_bos_token": false,
            "add_eos_token": false,
            "added_tokens_decoder": {},
            "bos_token": "<|endoftext|>",
            "chat_template": "test",
            "clean_up_tokenization_spaces": false,
            "eos_token": "<|endoftext|>",
            "errors": "replace",
            "model_max_length": 32768,
            "pad_token": "<|endoftext|>",
            "split_special_tokens": false,
            "tokenizer_class": "Qwen2Tokenizer",
            "unk_token": null
        }
        """
        try tokenizerConfigJSON.write(to: tokenizerConfigPath, atomically: true, encoding: .utf8)

        let tokenizerPath = path.appendingPathComponent("tokenizer.json")
        let tokenizerJSON = """
        {
            "version": "1.0",
            "truncation": null,
            "padding": null,
            "added_tokens": [],
            "normalizer": null,
            "pre_tokenizer": null,
            "post_processor": null,
            "decoder": null,
            "model": {
                "type": "BPE",
                "dropout": null,
                "unk_token": null,
                "continuing_subword_prefix": null,
                "end_of_word_suffix": null,
                "fuse_unk": false,
                "byte_fallback": false,
                "vocab": {
                    "<|endoftext|>": 0,
                    "Hello": 1,
                    "World": 2,
                    " ": 3,
                    "!": 4
                },
                "merges": []
            }
        }
        """
        try tokenizerJSON.write(to: tokenizerPath, atomically: true, encoding: .utf8)

        let weightsPath = path.appendingPathComponent("model.safetensors")
        let emptyWeights = Data()
        try emptyWeights.write(to: weightsPath)
    }
}

final class TextGenMockModelRegistry: ModelRegistryProtocol {
    private let tempDir: URL
    private let storageManager: StorageManager

    init() {
        self.tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextGenTests-\(UUID().uuidString)")

        self.storageManager = StorageManager(baseDirectory: tempDir)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "qwen2.5-7b-instruct-4bit",
                name: "Qwen2.5 7B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                approximateSizeGB: 4.0,
                memoryUsageGB: 4.0
            )
        ]
    }

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        let path = downloadPath(for: model)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path.path) else {
            return false
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles
            )
            return !contents.isEmpty
        } catch {
            return false
        }
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        return storageManager.modelsDirectory.appendingPathComponent(model.id)
    }
}
