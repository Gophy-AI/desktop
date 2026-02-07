import Testing
import Foundation
@testable import Gophy

@Suite("ModeController Tests")
struct ModeControllerTests {

    @Test("Meeting mode loads WhisperKit and nomic-embed")
    func testMeetingModeLoading() async throws {
        let mockTranscription = MockTranscriptionEngine()
        let mockTextGen = MockTextGenerationEngine()
        let mockEmbedding = MockEmbeddingEngine()
        let mockOCR = MockOCREngine()
        let mockRegistry = MockModelRegistry()

        let controller = ModeController(
            transcriptionEngine: mockTranscription,
            textGenerationEngine: mockTextGen,
            embeddingEngine: mockEmbedding,
            ocrEngine: mockOCR,
            modelRegistry: mockRegistry
        )

        var stateHistory: [ModeState] = []
        let stateTask = Task {
            for await state in controller.stateStream {
                stateHistory.append(state)
                if case .ready = state {
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        try await controller.switchMode(.meeting)

        try await Task.sleep(for: .milliseconds(100))
        stateTask.cancel()

        #expect(mockTranscription.loadCalled)
        #expect(!mockTextGen.loadCalled)
        #expect(mockEmbedding.loadCalled)
        let ocrLoadCalled1 = await mockOCR.getLoadCalled()
        #expect(!ocrLoadCalled1)
        #expect(controller.isReady)
        #expect(controller.currentMode == .meeting)

        #expect(stateHistory.contains(.loading))
        #expect(stateHistory.contains(.ready))
    }

    @Test("Document mode loads Qwen2.5-VL and nomic-embed")
    func testDocumentModeLoading() async throws {
        let mockTranscription = MockTranscriptionEngine()
        let mockTextGen = MockTextGenerationEngine()
        let mockEmbedding = MockEmbeddingEngine()
        let mockOCR = MockOCREngine()
        let mockRegistry = MockModelRegistry()

        let controller = ModeController(
            transcriptionEngine: mockTranscription,
            textGenerationEngine: mockTextGen,
            embeddingEngine: mockEmbedding,
            ocrEngine: mockOCR,
            modelRegistry: mockRegistry
        )

        var stateHistory: [ModeState] = []
        let stateTask = Task {
            for await state in controller.stateStream {
                stateHistory.append(state)
                if case .ready = state {
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        try await controller.switchMode(.document)

        try await Task.sleep(for: .milliseconds(100))
        stateTask.cancel()

        #expect(!mockTranscription.loadCalled)
        #expect(!mockTextGen.loadCalled)
        #expect(mockEmbedding.loadCalled)
        let ocrLoadCalled2 = await mockOCR.getLoadCalled()
        #expect(ocrLoadCalled2)
        #expect(controller.isReady)
        #expect(controller.currentMode == .document)

        #expect(stateHistory.contains(.loading))
        #expect(stateHistory.contains(.ready))
    }

    @Test("Mode switch unloads previous mode engines and loads new ones")
    func testModeSwitching() async throws {
        let mockTranscription = MockTranscriptionEngine()
        let mockTextGen = MockTextGenerationEngine()
        let mockEmbedding = MockEmbeddingEngine()
        let mockOCR = MockOCREngine()
        let mockRegistry = MockModelRegistry()

        let controller = ModeController(
            transcriptionEngine: mockTranscription,
            textGenerationEngine: mockTextGen,
            embeddingEngine: mockEmbedding,
            ocrEngine: mockOCR,
            modelRegistry: mockRegistry
        )

        try await controller.switchMode(.meeting)
        try await Task.sleep(for: .milliseconds(100))

        #expect(mockTranscription.loadCalled)
        #expect(!mockTextGen.loadCalled)
        let ocrLoadCalled3 = await mockOCR.getLoadCalled()
        #expect(!ocrLoadCalled3)

        mockTranscription.loadCalled = false
        mockTextGen.loadCalled = false

        var stateHistory: [ModeState] = []
        let stateTask = Task {
            for await state in controller.stateStream {
                stateHistory.append(state)
                if case .ready = state, stateHistory.count > 2 {
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        try await controller.switchMode(.document)

        try await Task.sleep(for: .milliseconds(100))
        stateTask.cancel()

        #expect(mockTranscription.unloadCalled)
        #expect(mockTextGen.unloadCalled)
        let ocrLoadCalled4 = await mockOCR.getLoadCalled()
        #expect(ocrLoadCalled4)
        #expect(controller.currentMode == .document)

        #expect(stateHistory.contains(.switching))
        #expect(stateHistory.contains(.ready))
    }

    @Test("State stream emits loading -> ready -> switching -> ready")
    func testStateStreamSequence() async throws {
        let mockTranscription = MockTranscriptionEngine()
        let mockTextGen = MockTextGenerationEngine()
        let mockEmbedding = MockEmbeddingEngine()
        let mockOCR = MockOCREngine()
        let mockRegistry = MockModelRegistry()

        let controller = ModeController(
            transcriptionEngine: mockTranscription,
            textGenerationEngine: mockTextGen,
            embeddingEngine: mockEmbedding,
            ocrEngine: mockOCR,
            modelRegistry: mockRegistry
        )

        var stateHistory: [ModeState] = []
        let stateTask = Task {
            for await state in controller.stateStream {
                stateHistory.append(state)
                if stateHistory.count >= 5 {
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        try await controller.switchMode(.meeting)
        try await Task.sleep(for: .milliseconds(100))

        try await controller.switchMode(.document)
        try await Task.sleep(for: .milliseconds(100))

        stateTask.cancel()

        #expect(stateHistory.count >= 4)

        var hasLoadingToReady = false
        for i in 0..<stateHistory.count-1 {
            if stateHistory[i] == .loading && stateHistory[i+1] == .ready {
                hasLoadingToReady = true
                break
            }
        }
        #expect(hasLoadingToReady)

        var hasSwitchingToReady = false
        for i in 0..<stateHistory.count-1 {
            if stateHistory[i] == .switching && stateHistory[i+1] == .ready {
                hasSwitchingToReady = true
                break
            }
        }
        #expect(hasSwitchingToReady)
    }

    @Test("Embedding engine stays loaded across mode switches")
    func testEmbeddingEngineStaysLoaded() async throws {
        let mockTranscription = MockTranscriptionEngine()
        let mockTextGen = MockTextGenerationEngine()
        let mockEmbedding = MockEmbeddingEngine()
        let mockOCR = MockOCREngine()
        let mockRegistry = MockModelRegistry()

        let controller = ModeController(
            transcriptionEngine: mockTranscription,
            textGenerationEngine: mockTextGen,
            embeddingEngine: mockEmbedding,
            ocrEngine: mockOCR,
            modelRegistry: mockRegistry
        )

        try await controller.switchMode(.meeting)
        try await Task.sleep(for: .milliseconds(100))

        #expect(mockEmbedding.loadCalled)
        #expect(!mockEmbedding.unloadCalled)

        mockEmbedding.loadCalled = false

        try await controller.switchMode(.document)
        try await Task.sleep(for: .milliseconds(100))

        #expect(!mockEmbedding.loadCalled)
        #expect(!mockEmbedding.unloadCalled)
    }
}

final class MockTranscriptionEngine: TranscriptionEngineProtocol, @unchecked Sendable {
    var loadCalled = false
    var unloadCalled = false
    var isLoaded = false

    func load() async throws {
        loadCalled = true
        isLoaded = true
    }

    func unload() {
        unloadCalled = true
        isLoaded = false
    }
}

final class MockTextGenerationEngine: TextGenerationEngineProtocol, @unchecked Sendable {
    var loadCalled = false
    var unloadCalled = false
    var isLoaded = false

    func load() async throws {
        loadCalled = true
        isLoaded = true
    }

    func unload() {
        unloadCalled = true
        isLoaded = false
    }
}

final class MockEmbeddingEngine: EmbeddingEngineProtocol, @unchecked Sendable {
    var loadCalled = false
    var unloadCalled = false
    var isLoaded = false

    func load() async throws {
        loadCalled = true
        isLoaded = true
    }

    func unload() {
        unloadCalled = true
        isLoaded = false
    }
}

actor MockOCREngine: OCREngineActorProtocol {
    var loadCalled = false
    var unloadCalled = false
    private var _isLoaded = false

    nonisolated var isLoaded: Bool {
        get async {
            await getIsLoaded()
        }
    }

    private func getIsLoaded() -> Bool {
        return _isLoaded
    }

    func load() async throws {
        loadCalled = true
        _isLoaded = true
    }

    func unload() async {
        unloadCalled = true
        _isLoaded = false
    }

    func getLoadCalled() -> Bool {
        return loadCalled
    }

    func getUnloadCalled() -> Bool {
        return unloadCalled
    }
}

final class MockModelRegistry: ModelRegistryProtocol, @unchecked Sendable {
    func availableModels() -> [ModelDefinition] {
        return [
            ModelDefinition(
                id: "whisperkit-large-v3-turbo",
                name: "WhisperKit large-v3-turbo",
                type: .stt,
                huggingFaceID: "argmaxinc/whisperkit-coreml-large-v3-turbo",
                approximateSizeGB: 1.5,
                memoryUsageGB: 1.5
            ),
            ModelDefinition(
                id: "qwen2.5-7b-instruct-4bit",
                name: "Qwen2.5 7B Instruct 4-bit",
                type: .textGen,
                huggingFaceID: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                approximateSizeGB: 4.0,
                memoryUsageGB: 4.0
            ),
            ModelDefinition(
                id: "qwen2.5-vl-7b-instruct-4bit",
                name: "Qwen2.5-VL 7B Instruct 4-bit",
                type: .ocr,
                huggingFaceID: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit",
                approximateSizeGB: 4.0,
                memoryUsageGB: 4.0
            ),
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

    func isDownloaded(_ model: ModelDefinition) -> Bool {
        return true
    }

    func downloadPath(for model: ModelDefinition) -> URL {
        return URL(fileURLWithPath: "/tmp/\(model.id)")
    }
}
