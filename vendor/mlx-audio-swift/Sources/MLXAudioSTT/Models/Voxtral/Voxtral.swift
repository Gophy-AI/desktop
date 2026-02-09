//
//  Voxtral.swift
//  MLXAudioSTT
//
// Voxtral STT model: multimodal LLM combining audio encoder with Llama decoder

import Foundation
import MLX
import MLXNN
import MLXAudioCore
import MLXLMCommon
import HuggingFace
import Tokenizers

// MARK: - Language Model Components

/// Simple Llama-compatible language model for Voxtral.
/// Implements the text decoder portion matching the Python LanguageModel class.
class VoxtralLanguageModel: Module, KVCacheDimensionProvider {
    let config: VoxtralTextConfig

    @ModuleInfo(key: "model") var model: VoxtralLlamaModel
    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    var kvHeads: [Int] {
        return (0..<config.numHiddenLayers).map { _ in config.numKeyValueHeads }
    }

    init(config: VoxtralTextConfig) {
        self.config = config
        self._model.wrappedValue = VoxtralLlamaModel(config: config)

        if !config.tieWordEmbeddings {
            self._lmHead.wrappedValue = Linear(config.hiddenSize, config.vocabSize, bias: false)
        }
    }

    func callAsFunction(
        inputs: MLXArray? = nil,
        cache: [KVCache]? = nil,
        inputEmbeddings: MLXArray? = nil
    ) -> MLXArray {
        let out = model(inputs, cache: cache, inputEmbeddings: inputEmbeddings)

        if let lmHead = lmHead {
            return lmHead(out)
        } else {
            return model.embedTokens.asLinear(out)
        }
    }

    var embedTokens: Embedding {
        return model.embedTokens
    }
}

/// Inner Llama model matching Python LlamaModel structure.
class VoxtralLlamaModel: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    let layers: [VoxtralLlamaDecoderLayer]
    let norm: RMSNorm

    init(config: VoxtralTextConfig) {
        precondition(config.vocabSize > 0)

        self._embedTokens.wrappedValue = Embedding(
            embeddingCount: config.vocabSize,
            dimensions: config.hiddenSize
        )

        self.layers = (0..<config.numHiddenLayers).map { _ in
            VoxtralLlamaDecoderLayer(config: config)
        }
        self.norm = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    func callAsFunction(
        _ inputs: MLXArray?,
        cache: [KVCache]? = nil,
        inputEmbeddings: MLXArray? = nil
    ) -> MLXArray {
        var h: MLXArray
        if let inputEmbeddings = inputEmbeddings {
            h = inputEmbeddings
        } else if let inputs = inputs {
            h = embedTokens(inputs)
        } else {
            fatalError("Either inputs or inputEmbeddings must be provided")
        }

        let mask = createAttentionMask(h: h, cache: cache?.first)

        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[i])
        }

        return norm(h)
    }
}

/// Llama decoder layer.
class VoxtralLlamaDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var selfAttn: VoxtralLlamaAttention
    @ModuleInfo(key: "mlp") var mlp: VoxtralLlamaMLP
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: RMSNorm

    init(config: VoxtralTextConfig) {
        self._selfAttn.wrappedValue = VoxtralLlamaAttention(config: config)
        self._mlp.wrappedValue = VoxtralLlamaMLP(config: config)
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        var r = selfAttn(inputLayerNorm(x), mask: mask, cache: cache)
        let h = x + r
        r = mlp(postAttentionLayerNorm(h))
        return h + r
    }
}

/// Llama attention with RoPE.
class VoxtralLlamaAttention: Module {
    let config: VoxtralTextConfig
    let scale: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    let rope: VoxtralRoPE

    init(config: VoxtralTextConfig) {
        self.config = config

        let dim = config.hiddenSize
        let heads = config.numAttentionHeads
        let kvHeads = config.numKeyValueHeads
        let headDim = config.headDim

        self.scale = pow(Float(headDim), -0.5)

        self._qProj.wrappedValue = Linear(dim, heads * headDim, bias: config.attentionBias)
        self._kProj.wrappedValue = Linear(dim, kvHeads * headDim, bias: config.attentionBias)
        self._vProj.wrappedValue = Linear(dim, kvHeads * headDim, bias: config.attentionBias)
        self._oProj.wrappedValue = Linear(heads * headDim, dim, bias: config.attentionBias)

        self.rope = VoxtralRoPE(
            dims: headDim,
            traditional: config.ropeTraditional,
            base: config.ropeTheta
        )
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let (B, L) = (x.dim(0), x.dim(1))
        let headDim = config.headDim

        var queries = qProj(x)
        var keys = kProj(x)
        var values = vProj(x)

        queries = queries.reshaped(B, L, config.numAttentionHeads, headDim).transposed(0, 2, 1, 3)
        keys = keys.reshaped(B, L, config.numKeyValueHeads, headDim).transposed(0, 2, 1, 3)
        values = values.reshaped(B, L, config.numKeyValueHeads, headDim).transposed(0, 2, 1, 3)

        if let cache = cache {
            queries = rope(queries, offset: cache.offset)
            keys = rope(keys, offset: cache.offset)
            (keys, values) = cache.update(keys: keys, values: values)
        } else {
            queries = rope(queries)
            keys = rope(keys)
        }

        let output = MLXFast.scaledDotProductAttention(
            queries: queries,
            keys: keys,
            values: values,
            scale: scale,
            mask: mask
        ).transposed(0, 2, 1, 3).reshaped(B, L, -1)

        return oProj(output)
    }
}

/// Llama MLP with SiLU activation.
class VoxtralLlamaMLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear

    init(config: VoxtralTextConfig) {
        self._gateProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: config.mlpBias)
        self._downProj.wrappedValue = Linear(config.intermediateSize, config.hiddenSize, bias: config.mlpBias)
        self._upProj.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: config.mlpBias)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        return downProj(silu(gateProj(x)) * upProj(x))
    }
}

/// RoPE implementation for Voxtral.
class VoxtralRoPE: Module {
    let dims: Int
    let traditional: Bool
    let base: Float
    let scale: Float

    init(dims: Int, traditional: Bool = false, base: Float = 10000.0, scale: Float = 1.0) {
        self.dims = dims
        self.traditional = traditional
        self.base = base
        self.scale = scale
        super.init()
    }

    func callAsFunction(_ x: MLXArray, offset: Int = 0) -> MLXArray {
        return MLXFast.RoPE(
            x,
            dimensions: dims,
            traditional: traditional,
            base: base,
            scale: scale,
            offset: offset
        )
    }
}

// MARK: - Audio Processing Constants

enum VoxtralAudioConstants {
    static let sampleRate = 16000
    static let nFft = 400
    static let hopLength = 160
}

// MARK: - Voxtral Model

/// Voxtral multimodal STT model.
///
/// Architecture: Audio encoder (Conv1d + transformer) -> MultiModalProjector -> Llama LM
/// Audio features replace audio_token_id positions in the prompt.
public class VoxtralModel: Module {
    public let config: VoxtralModelConfig
    public let vocabSize: Int

    @ModuleInfo(key: "audio_tower") var audioTower: VoxtralEncoder
    @ModuleInfo(key: "multi_modal_projector") var multiModalProjector: VoxtralMultiModalProjector
    @ModuleInfo(key: "language_model") var languageModel: VoxtralLanguageModel

    public var tokenizer: Tokenizer?

    public init(config: VoxtralModelConfig) {
        self.config = config
        self.vocabSize = config.textConfig.vocabSize

        self._audioTower.wrappedValue = VoxtralEncoder(config: config.audioConfig)
        self._multiModalProjector.wrappedValue = VoxtralMultiModalProjector(config: config)
        self._languageModel.wrappedValue = VoxtralLanguageModel(config: config.textConfig)
    }

    // MARK: - Audio Embedding

    /// Get audio embeddings from raw features.
    public func getAudioEmbeds(_ audioFeatures: MLXArray) -> MLXArray {
        let audioEncoded = audioTower(audioFeatures)
        let audioReshaped = audioEncoded.reshaped([-1, config.audioConfig.intermediateSize])
        return multiModalProjector(audioReshaped)
    }

    /// Merge audio embeddings into text embeddings at audio_token_id positions.
    private func mergeInputEmbeddings(
        inputIds: MLXArray,
        inputFeatures: MLXArray?,
        cache: [KVCache]?
    ) -> MLXArray {
        var inputsEmbeds: MLXArray? = nil
        if inputIds.size > 0 {
            inputsEmbeds = languageModel.embedTokens(inputIds)
        }

        // Only process audio if provided and cache is empty
        if let inputFeatures = inputFeatures, (cache == nil || cache?.first?.offset == 0) {
            let audioEmbeds = getAudioEmbeds(inputFeatures)

            if let inputsEmbeds = inputsEmbeds {
                // Replace audio_token_id positions with audio embeddings
                let audioTokenMask = inputIds .== Int32(config.audioTokenId)

                // Find audio token positions
                var audioTokenPositions: [Int] = []
                for i in 0..<audioTokenMask.size {
                    if audioTokenMask[i].item(Bool.self) {
                        audioTokenPositions.append(i)
                    }
                }

                // Replace embeddings at audio token positions
                var inputsEmbedsFlat = inputsEmbeds.reshaped([-1, inputsEmbeds.shape.last!])
                for (idx, pos) in audioTokenPositions.enumerated() where idx < audioEmbeds.shape[0] {
                    inputsEmbedsFlat[pos] = audioEmbeds[idx]
                }

                return inputsEmbedsFlat.reshaped(inputsEmbeds.shape)
            } else {
                return audioEmbeds
            }
        }

        return inputsEmbeds ?? languageModel.embedTokens(inputIds)
    }

    /// Forward pass.
    public func callAsFunction(
        inputIds: MLXArray,
        inputFeatures: MLXArray? = nil,
        cache: [KVCache]? = nil
    ) -> MLXArray {
        let inputsEmbeds = mergeInputEmbeddings(
            inputIds: inputIds,
            inputFeatures: inputFeatures,
            cache: cache
        )

        return languageModel(cache: cache, inputEmbeddings: inputsEmbeds)
    }

    // MARK: - Audio Preprocessing

    /// Preprocess audio to mel spectrogram.
    public func preprocessAudio(_ audio: MLXArray) -> MLXArray {
        let nMels = config.audioConfig.numMelBins

        // If already 3D (batch, mels, seq), assume it's mel spectrogram
        if audio.ndim == 3 {
            return audio
        }

        // Compute mel spectrogram
        let melSpec = MLXAudioCore.computeMelSpectrogram(
            audio: audio,
            sampleRate: VoxtralAudioConstants.sampleRate,
            nFft: VoxtralAudioConstants.nFft,
            hopLength: VoxtralAudioConstants.hopLength,
            nMels: nMels
        )

        // Transpose to (batch, mels, seq) format expected by Conv1d
        // melSpec is (seq, mels), need (1, mels, seq)
        return melSpec.transposed(0, 1).expandedDimensions(axis: 0)
    }

    // MARK: - Generation

    /// Generate transcription from audio.
    public func generate(
        audio: MLXArray,
        maxTokens: Int = 128,
        temperature: Float = 0.0,
        language: String = "en"
    ) -> STTOutput {
        guard let tokenizer = tokenizer else {
            fatalError("Tokenizer not loaded")
        }

        let startTime = Date()

        // Preprocess audio
        let mel = preprocessAudio(audio)

        // Build prompt with audio tokens
        // Simplified prompt construction - in production would use processor
        let promptText = "<|user|>\n"
        var tokens = tokenizer.encode(text: promptText)

        // Reserve positions in token sequence for audio embeddings (marked by audio_token_id)
        let audioSeqLen = mel.shape[2] / 2  // Encoder downsamples by 2
        tokens.append(contentsOf: Array(repeating: config.audioTokenId, count: audioSeqLen))

        let suffixText = "\nPlease transcribe this audio into text<|assistant|>\n"
        tokens.append(contentsOf: tokenizer.encode(text: suffixText))

        let inputIds = MLXArray(tokens.map { Int32($0) }).expandedDimensions(axis: 0)
        let promptTokenCount = inputIds.shape[1]

        // Create cache and run initial forward pass
        let cache = makeCache()
        var logits = self(inputIds: inputIds, inputFeatures: mel, cache: cache)
        eval(logits)

        // Generate tokens
        var generatedTokens: [Int] = []
        let eosTokenIds = [config.textConfig.eosTokenId]

        for _ in 0..<maxTokens {
            var lastLogits = logits[0..., -1, 0...]
            if temperature > 0 {
                lastLogits = lastLogits / temperature
            }

            let nextToken = lastLogits.argMax(axis: -1).item(Int.self)

            if eosTokenIds.contains(nextToken) {
                break
            }

            generatedTokens.append(nextToken)

            // Step to next token
            let nextTokenArray = MLXArray([Int32(nextToken)]).expandedDimensions(axis: 0)
            logits = languageModel(inputs: nextTokenArray, cache: cache)
            eval(logits)
        }

        let endTime = Date()
        Memory.clearCache()

        let text = tokenizer.decode(tokens: generatedTokens)
        let totalTime = endTime.timeIntervalSince(startTime)

        return STTOutput(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: promptTokenCount,
            generationTokens: generatedTokens.count,
            totalTokens: promptTokenCount + generatedTokens.count,
            promptTps: Double(promptTokenCount) / totalTime,
            generationTps: Double(generatedTokens.count) / totalTime,
            totalTime: totalTime,
            peakMemoryUsage: Double(Memory.peakMemory) / 1e9
        )
    }

    /// Generate transcription with streaming.
    public func generateStream(
        audio: MLXArray,
        maxTokens: Int = 128,
        temperature: Float = 0.0
    ) -> AsyncThrowingStream<STTGeneration, Error> {
        AsyncThrowingStream { continuation in
            do {
                guard let tokenizer = self.tokenizer else {
                    throw STTError.modelNotInitialized("Tokenizer not loaded")
                }

                let startTime = Date()

                // Preprocess audio
                let mel = self.preprocessAudio(audio)

                // Build prompt
                let promptText = "<|user|>\n"
                var tokens = tokenizer.encode(text: promptText)
                let audioSeqLen = mel.shape[2] / 2
                tokens.append(contentsOf: Array(repeating: self.config.audioTokenId, count: audioSeqLen))
                let suffixText = "\nPlease transcribe this audio into text<|assistant|>\n"
                tokens.append(contentsOf: tokenizer.encode(text: suffixText))

                let inputIds = MLXArray(tokens.map { Int32($0) }).expandedDimensions(axis: 0)
                let promptTokenCount = inputIds.shape[1]

                // Initial forward pass
                let cache = self.makeCache()
                var logits = self(inputIds: inputIds, inputFeatures: mel, cache: cache)
                eval(logits)

                let prefillEndTime = Date()
                let prefillTime = prefillEndTime.timeIntervalSince(startTime)

                // Generate tokens
                var generatedTokens: [Int] = []
                let eosTokenIds = [self.config.textConfig.eosTokenId]

                for _ in 0..<maxTokens {
                    var lastLogits = logits[0..., -1, 0...]
                    if temperature > 0 {
                        lastLogits = lastLogits / temperature
                    }

                    let nextToken = lastLogits.argMax(axis: -1).item(Int.self)

                    if eosTokenIds.contains(nextToken) {
                        break
                    }

                    generatedTokens.append(nextToken)

                    // Emit token
                    let tokenText = tokenizer.decode(tokens: [nextToken])
                    continuation.yield(.token(tokenText))

                    // Step to next
                    let nextTokenArray = MLXArray([Int32(nextToken)]).expandedDimensions(axis: 0)
                    logits = self.languageModel(inputs: nextTokenArray, cache: cache)
                    eval(logits)
                }

                let endTime = Date()
                let generateTime = endTime.timeIntervalSince(prefillEndTime)
                let totalTime = endTime.timeIntervalSince(startTime)

                Memory.clearCache()

                // Emit info
                let tokensPerSecond = generateTime > 0 ? Double(generatedTokens.count) / generateTime : 0
                let peakMemory = Double(Memory.peakMemory) / 1e9
                let info = STTGenerationInfo(
                    promptTokenCount: promptTokenCount,
                    generationTokenCount: generatedTokens.count,
                    prefillTime: prefillTime,
                    generateTime: generateTime,
                    tokensPerSecond: tokensPerSecond,
                    peakMemoryUsage: peakMemory
                )
                continuation.yield(.info(info))

                // Emit result
                let text = tokenizer.decode(tokens: generatedTokens)
                let output = STTOutput(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    promptTokens: promptTokenCount,
                    generationTokens: generatedTokens.count,
                    totalTokens: promptTokenCount + generatedTokens.count,
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

    /// Create KV cache for generation.
    public func makeCache() -> [KVCache] {
        return (0..<config.textConfig.numHiddenLayers).map { _ in
            KVCacheSimple()
        }
    }

    // MARK: - Weight Loading

    /// Sanitize weights: transpose Conv1d weights.
    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var sanitized: [String: MLXArray] = [:]

        for (k, v) in weights {
            if k.contains("conv") && k.contains("weight") {
                // Transpose Conv1d weights if needed (swap dims -1 and -2)
                if v.ndim == 3 && v.shape[2] < v.shape[1] {
                    sanitized[k] = v.transposed(0, 2, 1)
                } else {
                    sanitized[k] = v
                }
            } else {
                sanitized[k] = v
            }
        }

        return sanitized
    }

    /// Load model from pretrained weights.
    public static func fromPretrained(_ modelPath: String) async throws -> VoxtralModel {
        let client = HubClient.default
        let cache = client.cache ?? HubCache.default

        guard let repoID = Repo.ID(rawValue: modelPath) else {
            throw NSError(
                domain: "VoxtralModel",
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
        let config = try JSONDecoder().decode(VoxtralModelConfig.self, from: configData)

        // Create model
        let model = VoxtralModel(config: config)

        // Load tokenizer — Mistral models use tekken.json (tiktoken-style BPE),
        // which swift-transformers' AutoTokenizer cannot parse. Use TekkenTokenizer directly.
        let tekkenPath = modelDir.appendingPathComponent("tekken.json")
        if FileManager.default.fileExists(atPath: tekkenPath.path) {
            model.tokenizer = try TekkenTokenizer(url: tekkenPath)
        } else {
            model.tokenizer = try await AutoTokenizer.from(modelFolder: modelDir)
        }

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
