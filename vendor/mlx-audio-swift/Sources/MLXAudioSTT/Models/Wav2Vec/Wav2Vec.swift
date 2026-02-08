//
//  Wav2Vec.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation
import MLX
import MLXNN
import HuggingFace

public class Wav2Vec2Model: Module {
    public let config: Wav2VecModelConfig

    @ModuleInfo(key: "feature_extractor") var featureExtractor: Wav2Vec2FeatureEncoder
    @ModuleInfo(key: "feature_projection") var featureProjection: Wav2Vec2FeatureProjection
    @ModuleInfo var encoder: Module
    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    public init(config: Wav2VecModelConfig) {
        self.config = config

        self._featureExtractor.wrappedValue = Wav2Vec2FeatureEncoder(config: config)
        self._featureProjection.wrappedValue = Wav2Vec2FeatureProjection(config: config)

        if config.doStableLayerNorm {
            self._encoder.wrappedValue = Wav2Vec2EncoderStableLayerNorm(config: config)
        } else {
            self._encoder.wrappedValue = Wav2Vec2Encoder(config: config)
        }

        if let vocabSize = config.vocabSize {
            self._lmHead.wrappedValue = Linear(config.hiddenSize, vocabSize, bias: false)
        }
    }

    public func callAsFunction(
        inputValues: MLXArray,
        attentionMask: MLXArray? = nil
    ) -> Wav2Vec2BaseModelOutput {
        var extractFeatures = featureExtractor(inputValues)
        extractFeatures = extractFeatures.transposed(0, 2, 1)

        let (hiddenStates, extractFeaturesNorm) = featureProjection(extractFeatures)

        let encoderOutput: Wav2Vec2BaseModelOutput
        if let encoder = encoder as? Wav2Vec2Encoder {
            encoderOutput = encoder(hiddenStates, attentionMask: attentionMask)
        } else if let encoder = encoder as? Wav2Vec2EncoderStableLayerNorm {
            encoderOutput = encoder(hiddenStates, attentionMask: attentionMask)
        } else {
            fatalError("Unknown encoder type")
        }

        return Wav2Vec2BaseModelOutput(
            lastHiddenState: encoderOutput.lastHiddenState,
            extractFeatures: extractFeaturesNorm,
            hiddenStates: encoderOutput.hiddenStates
        )
    }

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var sanitized: [String: MLXArray] = [:]

        for (k, v) in weights {
            var newKey = k
            var newValue = v

            if newKey.hasPrefix("wav2vec2.") {
                newKey = String(newKey.dropFirst("wav2vec2.".count))
            }

            if newKey.contains("lm_head.") || newKey.contains("quantizer.") || newKey.hasPrefix("project_") || newKey == "masked_spec_embed" {
                continue
            }

            if newKey.contains(".parametrizations.weight.original0") {
                newKey = newKey.replacingOccurrences(of: ".parametrizations.weight.original0", with: ".weight_g")
                newValue = newValue.swappedAxes(1, 2)
            } else if newKey.contains(".parametrizations.weight.original1") {
                newKey = newKey.replacingOccurrences(of: ".parametrizations.weight.original1", with: ".weight_v")
                newValue = newValue.swappedAxes(1, 2)
            } else if newKey.hasSuffix(".conv.weight_v") || newKey.hasSuffix(".conv.weight_g") {
                newValue = newValue.swappedAxes(1, 2)
            } else if newKey.hasSuffix(".conv.weight") {
                newValue = newValue.swappedAxes(1, 2)
            }

            sanitized[newKey] = newValue
        }

        return sanitized
    }

    public func generate(audio: MLXArray) -> STTOutput {
        guard let lmHead = lmHead else {
            return STTOutput(text: "No CTC head available", language: nil)
        }

        let startTime = Date()

        let output = self(inputValues: audio, attentionMask: nil)
        let logits = lmHead(output.lastHiddenState)

        let tokens = argMax(logits, axis: -1)

        var decodedTokens: [Int] = []
        var prevToken = -1

        for i in 0..<tokens.shape[1] {
            let token = tokens[0, i].item(Int.self)
            if token != 0 && token != prevToken {
                decodedTokens.append(token)
            }
            prevToken = token
        }

        let text = decodedTokens.map { String($0) }.joined(separator: " ")

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        Memory.clearCache()

        return STTOutput(
            text: text,
            language: nil,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    public static func fromPretrained(_ modelPath: String) async throws -> Wav2Vec2Model {
        let client = HubClient.default
        let cache = client.cache ?? HubCache.default

        guard let repoID = Repo.ID(rawValue: modelPath) else {
            throw NSError(
                domain: "Wav2Vec2Model",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repository ID: \(modelPath)"]
            )
        }

        let modelDir = try await resolveOrDownloadModel(
            client: client,
            cache: cache,
            repoID: repoID
        )

        let configPath = modelDir.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(Wav2VecModelConfig.self, from: configData)

        let model = Wav2Vec2Model(config: config)

        var weights: [String: MLXArray] = [:]
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
        let safetensorFiles = files.filter { $0.pathExtension == "safetensors" }

        for file in safetensorFiles {
            let fileWeights = try MLX.loadArrays(url: file)
            weights.merge(fileWeights) { _, new in new }
        }

        let sanitizedWeights = model.sanitize(weights: weights)

        try model.update(parameters: ModuleParameters.unflattened(sanitizedWeights), verify: [.all])

        eval(model)

        return model
    }

    private static func resolveOrDownloadModel(
        client: HubClient,
        cache: HubCache,
        repoID: Repo.ID
    ) async throws -> URL {
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        let modelDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)

        let configPath = modelDir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            let files = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            let hasSafetensors = files?.contains { $0.pathExtension == "safetensors" } ?? false

            if hasSafetensors {
                print("Using cached model at: \(modelDir.path)")
                return modelDir
            }
        }

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        print("Downloading model \(repoID)...")
        _ = try await client.downloadSnapshot(
            of: repoID,
            kind: .model,
            to: modelDir,
            revision: "main",
            progressHandler: { progress in
                print("\(progress.completedUnitCount)/\(progress.totalUnitCount) files")
            }
        )

        print("Model downloaded to: \(modelDir.path)")
        return modelDir
    }
}
