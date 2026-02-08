//
//  Whisper.swift
//  MLXAudioSTT
//
//  Whisper STT model matching mlx-audio Python implementation.
//

import Foundation
import MLX
import MLXNN
import MLXAudioCore
import MLXLMCommon
import HuggingFace
import Tokenizers

// MARK: - Decoding Result

/// Result from Whisper decoding with detailed statistics.
public struct DecodingResult {
    public let audioFeatures: MLXArray
    public let language: String
    public let languageProbs: [String: Float]
    public let tokens: [Int]
    public let text: String
    public let avgLogprob: Float
    public let noSpeechProb: Float
    public let temperature: Float
    public let compressionRatio: Float

    public init(
        audioFeatures: MLXArray,
        language: String,
        languageProbs: [String: Float],
        tokens: [Int],
        text: String,
        avgLogprob: Float,
        noSpeechProb: Float,
        temperature: Float,
        compressionRatio: Float
    ) {
        self.audioFeatures = audioFeatures
        self.language = language
        self.languageProbs = languageProbs
        self.tokens = tokens
        self.text = text
        self.avgLogprob = avgLogprob
        self.noSpeechProb = noSpeechProb
        self.temperature = temperature
        self.compressionRatio = compressionRatio
    }
}

// MARK: - Tokenizer Wrapper

/// Wrapper around HuggingFace tokenizer providing Whisper-compatible interface.
public class HFTokenizerWrapper {
    let tokenizer: Tokenizer
    public let multilingual: Bool
    public let language: String
    public let task: String

    public init(tokenizer: Tokenizer, multilingual: Bool = true, language: String = "en", task: String = "transcribe") {
        self.tokenizer = tokenizer
        self.multilingual = multilingual
        self.language = language
        self.task = task
    }

    public func encode(_ text: String) -> [Int] {
        return tokenizer.encode(text: text)
    }

    public func decode(_ tokens: [Int]) -> String {
        return tokenizer.decode(tokens: tokens)
    }

    // Whisper special token IDs (hardcoded defaults for Whisper tokenizer)
    public var eot: Int { 50257 }  // End of transcript
    public var sot: Int { 50258 }  // Start of transcript
    public var noTimestamps: Int { 50363 }  // No timestamps token
    public var transcribeToken: Int { 50359 }  // Transcribe task
    public var translateToken: Int { 50358 }  // Translate task
}

// MARK: - Whisper Model

/// Whisper speech-to-text model.
public class WhisperModel: Module {
    public let config: WhisperModelConfig
    public let dims: ModelDimensions
    public let dtype: DType

    @ModuleInfo(key: "encoder") var encoder: WhisperAudioEncoder
    @ModuleInfo(key: "decoder") var decoder: WhisperTextDecoder

    public var tokenizer: HFTokenizerWrapper?

    public init(config: WhisperModelConfig, dtype: DType = .float16) {
        self.config = config
        self.dims = config.dimensions
        self.dtype = dtype

        self._encoder.wrappedValue = WhisperAudioEncoder(config: dims, dtype: dtype)
        self._decoder.wrappedValue = WhisperTextDecoder(config: dims, dtype: dtype)
    }

    // MARK: - Core Methods

    /// Encode audio mel spectrogram to features.
    public func encodeAudio(_ mel: MLXArray) -> MLXArray {
        return encoder(mel)
    }

    /// Decode tokens with encoder features.
    public func decodeTokens(_ tokens: MLXArray, audioFeatures: MLXArray, kvCache: [((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)]? = nil) -> (MLXArray, [((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)], [MLXArray?]) {
        return decoder(tokens, xa: audioFeatures, kvCache: kvCache)
    }

    /// Detect language from audio mel spectrogram.
    public func detectLanguage(_ mel: MLXArray) -> [String: Float] {
        // Encode audio
        let audioFeatures = encodeAudio(mel)

        // Simple language detection stub (full implementation requires language tokens)
        // For now, return English with high confidence
        return ["en": 1.0]
    }

    /// Generate transcription from audio.
    public func generate(
        audio: MLXArray,
        maxTokens: Int = 224,
        temperature: Float = 0.0
    ) -> STTOutput {
        guard let tokenizer = tokenizer else {
            fatalError("Tokenizer not loaded")
        }

        let startTime = Date()

        // Preprocess audio to mel spectrogram
        let mel = preprocessAudio(audio)

        // Encode audio
        let audioFeatures = encodeAudio(mel)
        eval(audioFeatures)

        // Initialize with start of transcript tokens
        var tokens = [tokenizer.sot]
        if tokenizer.multilingual {
            // Add language token (simplified: use transcribe token)
            tokens.append(tokenizer.transcribeToken)
        }
        tokens.append(tokenizer.noTimestamps)

        let promptTokenCount = tokens.count

        // Generate tokens
        var kvCache: [((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)]? = nil

        for _ in 0..<maxTokens {
            let tokenArray = MLXArray(tokens.map { Int32($0) }).expandedDimensions(axis: 0)
            let (logits, newCache, _) = decodeTokens(tokenArray, audioFeatures: audioFeatures, kvCache: kvCache)
            kvCache = newCache

            // Sample next token
            var lastLogits = logits[0..., -1, 0...]
            if temperature > 0 {
                lastLogits = lastLogits / temperature
            }
            let nextToken = Int(lastLogits.argMax(axis: -1).item(Int32.self))

            if nextToken == tokenizer.eot {
                break
            }

            tokens.append(nextToken)
        }

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        // Decode text
        let textTokens = Array(tokens.dropFirst(promptTokenCount))
        let text = tokenizer.decode(textTokens)

        Memory.clearCache()

        return STTOutput(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: promptTokenCount,
            generationTokens: textTokens.count,
            totalTokens: tokens.count,
            promptTps: Double(promptTokenCount) / totalTime,
            generationTps: Double(textTokens.count) / totalTime,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    /// Generate transcription with streaming.
    public func generateStream(
        audio: MLXArray,
        maxTokens: Int = 224,
        temperature: Float = 0.0
    ) -> AsyncThrowingStream<STTGeneration, Error> {
        AsyncThrowingStream { continuation in
            do {
                guard let tokenizer = self.tokenizer else {
                    throw STTError.modelNotInitialized("Tokenizer not loaded")
                }

                let startTime = Date()

                // Preprocess and encode audio
                let mel = self.preprocessAudio(audio)
                let audioFeatures = self.encodeAudio(mel)
                eval(audioFeatures)

                let prefillEndTime = Date()
                let prefillTime = prefillEndTime.timeIntervalSince(startTime)

                // Initialize tokens
                var tokens = [tokenizer.sot]
                if tokenizer.multilingual {
                    tokens.append(tokenizer.transcribeToken)
                }
                tokens.append(tokenizer.noTimestamps)

                let promptTokenCount = tokens.count
                let generateStartTime = Date()

                var kvCache: [((MLXArray, MLXArray)?, (MLXArray, MLXArray)?)]? = nil

                // Generate tokens
                for _ in 0..<maxTokens {
                    let tokenArray = MLXArray(tokens.map { Int32($0) }).expandedDimensions(axis: 0)
                    let (logits, newCache, _) = self.decodeTokens(tokenArray, audioFeatures: audioFeatures, kvCache: kvCache)
                    kvCache = newCache

                    var lastLogits = logits[0..., -1, 0...]
                    if temperature > 0 {
                        lastLogits = lastLogits / temperature
                    }
                    let nextToken = Int(lastLogits.argMax(axis: -1).item(Int32.self))

                    if nextToken == tokenizer.eot {
                        break
                    }

                    tokens.append(nextToken)

                    // Emit token
                    let tokenText = tokenizer.decode([nextToken])
                    continuation.yield(.token(tokenText))
                }

                let endTime = Date()
                let generateTime = endTime.timeIntervalSince(generateStartTime)
                let totalTime = endTime.timeIntervalSince(startTime)

                Memory.clearCache()

                let textTokens = Array(tokens.dropFirst(promptTokenCount))
                let tokensPerSecond = generateTime > 0 ? Double(textTokens.count) / generateTime : 0
                let peakMemory = Double(Memory.peakMemory) / 1e9

                // Emit info
                let info = STTGenerationInfo(
                    promptTokenCount: promptTokenCount,
                    generationTokenCount: textTokens.count,
                    prefillTime: prefillTime,
                    generateTime: generateTime,
                    tokensPerSecond: tokensPerSecond,
                    peakMemoryUsage: peakMemory
                )
                continuation.yield(.info(info))

                // Emit result
                let text = tokenizer.decode(textTokens)
                let output = STTOutput(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    promptTokens: promptTokenCount,
                    generationTokens: textTokens.count,
                    totalTokens: tokens.count,
                    promptTps: Double(promptTokenCount) / prefillTime,
                    generationTps: tokensPerSecond,
                    totalTime: totalTime,
                    peakMemoryUsage: peakMemory
                )
                continuation.yield(.result(output))

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Helpers

    /// Preprocess audio to mel spectrogram.
    public func preprocessAudio(_ audio: MLXArray) -> MLXArray {
        // Pad or trim to 30 seconds
        let paddedAudio = padOrTrim(audio, length: WhisperAudioConstants.nSamples)

        // Compute log-mel spectrogram (returns (n_mels, n_frames))
        let melSpec = logMelSpectrogram(audio: paddedAudio, nMels: dims.nMels)

        // Add batch dimension: (n_mels, n_frames) -> (1, n_mels, n_frames)
        return melSpec.expandedDimensions(axis: 0)
    }

    /// Sanitize weights for loading.
    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var sanitized: [String: MLXArray] = [:]

        // Key remapping from HuggingFace to MLX format
        let keyMap: [(String, String?)] = [
            ("model.encoder.embed_positions.weight", nil),  // Skip, computed in MLX
            ("model.encoder.layer_norm.", "encoder.ln_post."),
            ("model.encoder.layers.", "encoder.blocks."),
            ("model.decoder.layer_norm.", "decoder.ln."),
            ("model.decoder.layers.", "decoder.blocks."),
            ("model.decoder.embed_positions.weight", "decoder.positional_embedding"),
            ("model.decoder.embed_tokens.", "decoder.token_embedding."),
            (".self_attn_layer_norm.", ".attn_ln."),
            (".final_layer_norm.", ".mlp_ln."),
            (".encoder_attn_layer_norm.", ".cross_attn_ln."),
            (".fc1.", ".mlp1."),
            (".fc2.", ".mlp2."),
            (".self_attn.q_proj.", ".attn.query."),
            (".self_attn.k_proj.", ".attn.key."),
            (".self_attn.v_proj.", ".attn.value."),
            (".self_attn.out_proj.", ".attn.out."),
            (".encoder_attn.q_proj.", ".cross_attn.query."),
            (".encoder_attn.k_proj.", ".cross_attn.key."),
            (".encoder_attn.v_proj.", ".cross_attn.value."),
            (".encoder_attn.out_proj.", ".cross_attn.out."),
        ]

        let isHfFormat = weights.keys.contains { $0.hasPrefix("model.") }

        for (k, v) in weights {
            var newKey = k
            var newValue = v

            if isHfFormat {
                // Remove 'model.' prefix
                if newKey.hasPrefix("model.") {
                    newKey = String(newKey.dropFirst(6))
                }

                // Apply key remapping
                var skip = false
                for (old, new) in keyMap {
                    if newKey.contains(old) {
                        if let new = new {
                            newKey = newKey.replacingOccurrences(of: old, with: new)
                        } else {
                            skip = true
                            break
                        }
                    }
                }

                if skip {
                    continue
                }

                // Transpose Conv1d weights: HF uses (out, in, kernel), MLX uses (out, kernel, in)
                if newKey.contains("conv1.weight") || newKey.contains("conv2.weight") {
                    if newValue.ndim == 3 {
                        newValue = newValue.transposed(0, 2, 1)
                    }
                }
            }

            // Convert to model dtype
            if newValue.dtype != dtype && newValue.dtype != .uint32 {
                newValue = newValue.asType(dtype)
            }

            sanitized[newKey] = newValue
        }

        return sanitized
    }

    // MARK: - Model Loading

    /// Load model from pretrained weights.
    public static func fromPretrained(_ modelPath: String) async throws -> WhisperModel {
        let client = HubClient.default
        let cache = client.cache ?? HubCache.default

        guard let repoID = Repo.ID(rawValue: modelPath) else {
            throw NSError(
                domain: "WhisperModel",
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
        let config = try JSONDecoder().decode(WhisperModelConfig.self, from: configData)

        // Create model
        let model = WhisperModel(config: config)

        // Load tokenizer
        let hfTokenizer = try await AutoTokenizer.from(modelFolder: modelDir)
        model.tokenizer = HFTokenizerWrapper(tokenizer: hfTokenizer)

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
        let sanitizedWeights = model.sanitize(weights: weights)

        // Quantize if needed
        if let perLayerQuantization = config.perLayerQuantization {
            print("Applying quantization from config...")
            quantize(model: model) { path, module in
                if sanitizedWeights["\(path).scales"] != nil {
                    return perLayerQuantization.quantization(layer: path)?.asTuple
                } else {
                    return nil
                }
            }
        }

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
