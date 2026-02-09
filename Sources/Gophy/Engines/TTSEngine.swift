import Foundation
import os.log
import MLX
import MLXAudioTTS
import MLXLMCommon

private let ttsLogger = Logger(subsystem: "com.gophy.app", category: "TTSEngine")

public enum TTSError: Error, Sendable {
    case modelNotLoaded
    case noModelAvailable
    case synthesizeFailed(String)
}

public protocol TTSModelProtocol: Sendable {
    func generate(text: String, voice: String?) async throws -> [Float]
    var sampleRate: Int { get }
}

public typealias TTSModelLoader = @Sendable (String) async throws -> any TTSModelProtocol

public final class TTSEngine: @unchecked Sendable {
    private var model: (any TTSModelProtocol)?
    private(set) public var isLoaded: Bool = false
    private let modelRegistry: any ModelRegistryProtocol
    private let ttsModelLoader: TTSModelLoader

    public init(
        modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared,
        ttsModelLoader: @escaping TTSModelLoader
    ) {
        self.modelRegistry = modelRegistry
        self.ttsModelLoader = ttsModelLoader
    }

    public convenience init(
        modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared
    ) {
        self.init(modelRegistry: modelRegistry, ttsModelLoader: { repoID in
            let model = try await TTSModelUtils.loadModel(modelRepo: repoID)
            return SpeechGenerationModelWrapper(model: model)
        })
    }

    public func load() async throws {
        let selectedId = UserDefaults.standard.string(forKey: "selectedTTSModelId") ?? "soprano-80m-bf16"
        let ttsModels = modelRegistry.availableModels().filter { $0.type == .tts }

        guard let ttsModel = ttsModels.first(where: { $0.id == selectedId && modelRegistry.isDownloaded($0) })
                ?? ttsModels.first(where: { modelRegistry.isDownloaded($0) })
        else {
            throw TTSError.noModelAvailable
        }

        ttsLogger.info("TTSEngine loading model: \(ttsModel.huggingFaceID, privacy: .public)")
        model = try await ttsModelLoader(ttsModel.huggingFaceID)
        isLoaded = true
        ttsLogger.info("TTSEngine loaded successfully")
    }

    public func synthesize(text: String, voice: String?) async throws -> [Float] {
        guard let model else {
            ttsLogger.error("TTSEngine.synthesize: model not loaded")
            throw TTSError.modelNotLoaded
        }

        ttsLogger.info("TTSEngine.synthesize: processing text of length \(text.count, privacy: .public)")
        return try await model.generate(text: text, voice: voice)
    }

    public func synthesizeStream(text: String, voice: String?) -> AsyncThrowingStream<[Float], Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let model = self.model else {
                    continuation.finish(throwing: TTSError.modelNotLoaded)
                    return
                }

                do {
                    let samples = try await model.generate(text: text, voice: voice)
                    continuation.yield(samples)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func unload() {
        model = nil
        isLoaded = false
        ttsLogger.info("TTSEngine unloaded")
    }
}

// MARK: - SpeechGenerationModel Wrapper

public final class SpeechGenerationModelWrapper: TTSModelProtocol, @unchecked Sendable {
    private let model: SpeechGenerationModel
    public let sampleRate: Int

    public init(model: SpeechGenerationModel) {
        self.model = model
        self.sampleRate = model.sampleRate
    }

    public func generate(text: String, voice: String?) async throws -> [Float] {
        let params = GenerateParameters()
        let result = try await model.generate(
            text: text,
            voice: voice,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: params
        )

        // Convert MLXArray to [Float]
        let floatArray = result.asArray(Float.self)
        return Array(floatArray)
    }
}
