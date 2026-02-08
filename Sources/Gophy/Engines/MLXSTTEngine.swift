import Foundation
import MLXAudioSTT
import MLX
import os.log

private let mlxSTTLogger = Logger(subsystem: "com.gophy.app", category: "MLXSTTEngine")

public enum MLXSTTError: Error, Sendable {
    case modelNotLoaded
    case noAudioRegistryModel
    case transcriptionFailed(String)
    case unsupportedModelType(String)
}

public protocol MLXSTTModelProtocol: Sendable {
    func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String
}

public enum MLXSTTModelType: String, Sendable {
    case glmasr
    case lasrCTC = "lasr-ctc"
    case whisper = "whisper-mlx"
    case parakeet
    case qwen3ASR = "qwen3-asr"
    case wav2vec
    case voxtral
    case voxtralRealtime = "voxtral-realtime"

    static func from(modelId: String) -> MLXSTTModelType? {
        let lowercased = modelId.lowercased()
        if lowercased.contains("glmasr") || lowercased.contains("glm-4-voice") {
            return .glmasr
        } else if lowercased.contains("parakeet") {
            return .parakeet
        } else if lowercased.contains("qwen3-asr") {
            return .qwen3ASR
        } else if lowercased.contains("wav2vec") {
            return .wav2vec
        } else if lowercased.contains("voxtral") && lowercased.contains("realtime") {
            return .voxtralRealtime
        } else if lowercased.contains("voxtral") {
            return .voxtral
        } else if lowercased.contains("whisper") {
            return .whisper
        } else if lowercased.contains("lasr") {
            return .lasrCTC
        }
        return nil
    }
}

public final class MLXSTTEngine: @unchecked Sendable {
    private var model: (any MLXSTTModelProtocol)?
    private(set) public var isLoaded: Bool = false
    private let modelRegistry: any ModelRegistryProtocol

    public init(
        modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared
    ) {
        self.modelRegistry = modelRegistry
    }

    public func load() async throws {
        let selectedId = UserDefaults.standard.string(forKey: "selectedSTTModelId") ?? ""
        let sttModels = modelRegistry.availableModels().filter { $0.type == .stt && $0.source == .audioRegistry }

        guard let sttModel = sttModels.first(where: { $0.id == selectedId && modelRegistry.isDownloaded($0) })
                ?? sttModels.first(where: { modelRegistry.isDownloaded($0) })
                ?? sttModels.first else {
            throw MLXSTTError.noAudioRegistryModel
        }

        mlxSTTLogger.info("MLXSTTEngine loading model: \(sttModel.huggingFaceID, privacy: .public)")

        guard let modelType = MLXSTTModelType.from(modelId: sttModel.id) else {
            throw MLXSTTError.unsupportedModelType(sttModel.id)
        }

        model = try await loadModel(repoID: sttModel.huggingFaceID, modelType: modelType)
        isLoaded = true
        mlxSTTLogger.info("MLXSTTEngine loaded successfully: \(modelType.rawValue, privacy: .public)")
    }

    public func transcribe(audioArray: [Float], sampleRate: Int = 16000, language: String? = nil) async throws -> [TranscriptionSegment] {
        guard let model else {
            mlxSTTLogger.error("MLXSTTEngine.transcribe: model not loaded")
            throw MLXSTTError.modelNotLoaded
        }

        mlxSTTLogger.info("MLXSTTEngine.transcribe: processing \(audioArray.count, privacy: .public) samples")
        let text = try model.transcribe(audio: audioArray, maxTokens: 4096, temperature: 0.0, language: language)

        guard !text.isEmpty else {
            return []
        }

        let duration = Double(audioArray.count) / Double(sampleRate)
        let segment = TranscriptionSegment(
            text: text,
            startTime: 0.0,
            endTime: duration
        )

        mlxSTTLogger.info("MLXSTTEngine.transcribe: returning 1 segment")
        return [segment]
    }

    public func unload() {
        model = nil
        isLoaded = false
        mlxSTTLogger.info("MLXSTTEngine unloaded")
    }

    private func loadModel(repoID: String, modelType: MLXSTTModelType) async throws -> any MLXSTTModelProtocol {
        switch modelType {
        case .glmasr:
            let model = try await GLMASRModel.fromPretrained(repoID)
            return GLMASRModelWrapper(model: model)
        case .lasrCTC:
            let model = try await LasrForCTC.fromPretrained(repoID)
            return LasrCTCModelWrapper(model: model)
        case .whisper:
            let model = try await WhisperModel.fromPretrained(repoID)
            return WhisperModelWrapper(model: model)
        case .parakeet:
            let model = try await ParakeetModel.fromPretrained(repoID)
            return ParakeetModelWrapper(model: model)
        case .qwen3ASR:
            let model = try await Qwen3ASRModel.fromPretrained(modelPath: repoID)
            return Qwen3ASRModelWrapper(model: model)
        case .wav2vec:
            let model = try await Wav2Vec2Model.fromPretrained(repoID)
            return Wav2VecModelWrapper(model: model)
        case .voxtral:
            let model = try await VoxtralModel.fromPretrained(repoID)
            return VoxtralModelWrapper(model: model)
        case .voxtralRealtime:
            let model = try await VoxtralRealtimeModel.fromPretrained(repoID)
            return VoxtralRealtimeModelWrapper(model: model)
        }
    }
}

// MARK: - Model Wrappers

public final class GLMASRModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: GLMASRModel

    public init(model: GLMASRModel) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let audioMLX = MLXArray(audio)
        let output = model.generate(
            audio: audioMLX,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return output.text
    }
}

public final class LasrCTCModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: LasrForCTC

    public init(model: LasrForCTC) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let audioMLX = MLXArray(audio)
        let output = model.generate(audio: audioMLX)
        return output.text
    }
}

public final class WhisperModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: WhisperModel

    public init(model: WhisperModel) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let audioMLX = MLXArray(audio)
        let output = model.generate(audio: audioMLX, maxTokens: maxTokens, temperature: temperature)
        return output.text
    }
}

public final class ParakeetModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: ParakeetModel

    public init(model: ParakeetModel) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let audioMLX = MLXArray(audio)
        let output = model.generate(audio: audioMLX)
        return output.text
    }
}

public final class Qwen3ASRModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: Qwen3ASRModel

    public init(model: Qwen3ASRModel) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let output = try model.generate(audio: audio, maxTokens: maxTokens, temperature: temperature)
        return output.text
    }
}

public final class Wav2VecModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: Wav2Vec2Model

    public init(model: Wav2Vec2Model) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let audioMLX = MLXArray(audio)
        let output = model.generate(audio: audioMLX)
        return output.text
    }
}

public final class VoxtralModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: VoxtralModel

    public init(model: VoxtralModel) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let audioMLX = MLXArray(audio)
        let lang = language ?? UserDefaults.standard.string(forKey: "languagePreference").flatMap({ AppLanguage(rawValue: $0)?.isoCode }) ?? "en"
        let output = model.generate(audio: audioMLX, maxTokens: maxTokens, temperature: temperature, language: lang)
        return output.text
    }
}

public final class VoxtralRealtimeModelWrapper: MLXSTTModelProtocol, @unchecked Sendable {
    private let model: VoxtralRealtimeModel

    public init(model: VoxtralRealtimeModel) {
        self.model = model
    }

    public func transcribe(audio: [Float], maxTokens: Int, temperature: Float, language: String?) throws -> String {
        let audioMLX = MLXArray(audio)
        let output = model.generate(audio: audioMLX, maxTokens: maxTokens, temperature: temperature)
        return output.text
    }
}
