//
//  Qwen3ASRWrapper.swift
//  MLXAudioSTT
//
// Wrapper that dispatches between Qwen3 ASR and Forced Aligner.
//

import Foundation
import MLX
import MLXNN

/// Top-level model wrapper that auto-detects model variant from config.
public enum Qwen3Model {
    case asr(Qwen3ASRModel)
    case aligner(ForcedAlignerModel)

    /// Load from pretrained, detecting model type from config.
    public static func fromPretrained(modelPath: String) throws -> Qwen3Model {
        let modelDirectory = URL(fileURLWithPath: modelPath)

        // Load config to detect type
        let configURL = modelDirectory.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)

        // Try to decode as dictionary to check model_type
        if let configDict = try JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let modelType = configDict["model_type"] as? String {

            if modelType == "qwen3_forced_aligner" {
                // Load as Forced Aligner
                let config = try JSONDecoder().decode(ForcedAlignerConfig.self, from: configData)
                let model = ForcedAlignerModel(config: config)
                return .aligner(model)
            } else {
                // Load as ASR (default)
                let config = try JSONDecoder().decode(Qwen3ASRModelConfig.self, from: configData)
                let model = Qwen3ASRModel(config: config)
                return .asr(model)
            }
        } else {
            // Default to ASR
            let config = try JSONDecoder().decode(Qwen3ASRModelConfig.self, from: configData)
            let model = Qwen3ASRModel(config: config)
            return .asr(model)
        }
    }

    /// Generate output based on model type.
    public func generate(audio: [Float], text: String? = nil, maxTokens: Int = 1024, temperature: Float = 0.0) throws -> Any {
        switch self {
        case .asr(let model):
            return try model.generate(audio: audio, maxTokens: maxTokens, temperature: temperature)
        case .aligner(let model):
            guard let text = text else {
                throw Qwen3Error.missingText
            }
            return try model.generate(audio: audio, text: text)
        }
    }
}

/// Errors for Qwen3 models.
public enum Qwen3Error: Error {
    case missingText
    case invalidModelType
}
