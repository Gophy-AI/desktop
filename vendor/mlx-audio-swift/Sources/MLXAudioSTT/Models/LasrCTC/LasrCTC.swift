//
//  LasrCTC.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation
import MLX
import MLXNN
import HuggingFace

// MARK: - CTC Decoding

private struct CTCSegment {
    let text: String
    let start: Float
    let end: Float
}

private func greedyCTCDecode(logits: MLXArray, blankId: Int = 0) -> [Int] {
    // Greedy decode: argmax per frame
    let tokens = logits.argMax(axis: -1).flattened()
    let tokenArray = tokens.asArray(Int32.self)

    var decoded: [Int] = []
    var prevToken: Int? = nil

    for token in tokenArray {
        let t = Int(token)
        // Skip blank tokens and consecutive duplicates
        if t != blankId && t != prevToken {
            decoded.append(t)
        }
        prevToken = t
    }

    return decoded
}

// MARK: - LASR CTC Model

/// LASR CTC model for speech-to-text transcription.
public class LasrForCTC: Module {
    public let config: LasrCTCModelConfig

    @ModuleInfo(key: "encoder") var encoder: LasrEncoder
    @ModuleInfo(key: "ctc_head") var ctcHead: Linear

    public init(config: LasrCTCModelConfig) {
        self.config = config
        self._encoder.wrappedValue = LasrEncoder(config: config.encoderConfig)
        self._ctcHead.wrappedValue = Linear(
            config.encoderConfig.hiddenSize,
            config.vocabSize,
            bias: true
        )
        super.init()
    }

    /// Forward pass returning logits.
    public func callAsFunction(_ inputFeatures: MLXArray) -> MLXArray {
        let hiddenStates = encoder(inputFeatures)
        let logits = ctcHead(hiddenStates)
        return logits
    }

    /// Generate transcription from audio features.
    ///
    /// - Parameters:
    ///   - audio: Mel spectrogram features with shape (batch, time, n_mels)
    ///   - vocabulary: Optional vocabulary mapping token IDs to strings
    ///   - sampleRate: Sample rate for timestamp calculation (default: 16000)
    ///   - hopLength: Hop length for timestamp calculation (default: 160)
    /// - Returns: STTOutput with transcribed text and optional segments
    public func generate(
        audio: MLXArray,
        vocabulary: [String]? = nil,
        sampleRate: Int = 16000,
        hopLength: Int = 160
    ) -> STTOutput {
        let startTime = Date()

        // Forward pass
        let logits = self(audio)
        eval(logits)

        // Greedy CTC decode
        let tokens = greedyCTCDecode(logits: logits[0])

        // Convert tokens to text
        var text = ""
        if let vocab = vocabulary {
            text = tokens.map { vocab[safe: $0] ?? "" }.joined()
        } else {
            // Fallback: represent as token IDs
            text = tokens.map { String($0) }.joined(separator: " ")
        }

        // Compute timestamps if vocabulary provided
        var segments: [[String: Any]]? = nil
        if vocabulary != nil && !tokens.isEmpty {
            // Calculate frame duration in seconds
            let frameDuration = Float(hopLength) / Float(sampleRate)
            // Note: In a full implementation, we would track frame indices during decoding
            // For now, we provide a simple segmentation
            segments = [[
                "start": 0.0,
                "end": Float(logits.shape[1]) * frameDuration,
                "text": text
            ]]
        }

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        Memory.clearCache()

        return STTOutput(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments,
            language: nil,
            promptTokens: 0,
            generationTokens: tokens.count,
            totalTokens: tokens.count,
            promptTps: 0.0,
            generationTps: Double(tokens.count) / totalTime,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    /// Sanitize weights from PyTorch/HuggingFace format to MLX format.
    public static func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var sanitized: [String: MLXArray] = [:]

        for (key, value) in weights {
            var newKey = key
            var newValue = value

            // Skip rotary embedding inverse frequencies (computed on-the-fly)
            if key.contains("rotary_emb.inv_freq") {
                continue
            }

            // Transpose Conv1d weights: (out, in, kernel) -> (out, kernel, in)
            if key.contains("conv") && key.contains("weight") && value.ndim == 3 {
                newValue = value.transposed(0, 2, 1)
            }

            // Handle CTC head bias: squeeze from (1, vocab) to (vocab,)
            if key == "ctc_head.bias" && value.ndim == 2 {
                newValue = squeezed(value, axis: 0)
            }

            // Handle CTC head weight: if it's Conv1d (3D), convert to Linear (2D)
            if key == "ctc_head.weight" && value.ndim == 3 {
                newValue = squeezed(value, axis: -1)
            }

            sanitized[newKey] = newValue
        }

        return sanitized
    }

    /// Load model from pretrained weights.
    public static func fromPretrained(_ modelPath: String) async throws -> LasrForCTC {
        let client = HubClient.default
        let cache = client.cache ?? HubCache.default

        guard let repoID = Repo.ID(rawValue: modelPath) else {
            throw NSError(
                domain: "LasrForCTC",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid repository ID: \(modelPath)"]
            )
        }

        let modelDir = try await resolveOrDownloadModel(
            client: client,
            cache: cache,
            repoID: repoID
        )

        // Load config
        let configPath = modelDir.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(LasrCTCModelConfig.self, from: configData)

        // Create model
        let model = LasrForCTC(config: config)

        // Load weights
        var weights: [String: MLXArray] = [:]
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
        let safetensorFiles = files.filter { $0.pathExtension == "safetensors" }

        for file in safetensorFiles {
            let fileWeights = try MLX.loadArrays(url: file)
            weights.merge(fileWeights) { _, new in new }
        }

        // Sanitize and load weights
        let sanitizedWeights = sanitize(weights: weights)
        try model.update(parameters: ModuleParameters.unflattened(sanitizedWeights), verify: [.all])

        eval(model)

        return model
    }

    // MARK: - Private Helpers

    private static func resolveOrDownloadModel(
        client: HubClient,
        cache: HubCache,
        repoID: Repo.ID
    ) async throws -> URL {
        let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
        let modelDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)

        // Check if model already exists
        let configPath = modelDir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            let files = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            let hasSafetensors = files?.contains { $0.pathExtension == "safetensors" } ?? false

            if hasSafetensors {
                print("Using cached model at: \(modelDir.path)")
                return modelDir
            }
        }

        // Create directory if needed
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Download model
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

// MARK: - Helper Extensions

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
