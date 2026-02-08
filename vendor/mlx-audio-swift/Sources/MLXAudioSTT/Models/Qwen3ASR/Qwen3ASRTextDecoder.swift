//
//  Qwen3ASRTextDecoder.swift
//  MLXAudioSTT
//
// Qwen3 ASR text decoder with Q/K RMSNorm.
//

import Foundation
import MLX
import MLXNN
import MLXLMCommon

// MARK: - Text Attention

/// Multi-headed attention for text decoder with Q/K RMSNorm and RoPE.
public class TextAttention: Module {
    let config: TextConfig
    let layerIdx: Int
    let hiddenSize: Int
    let numHeads: Int
    let numKvHeads: Int
    let headDim: Int
    let scale: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear
    @ModuleInfo(key: "q_norm") var qNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var kNorm: RMSNorm
    @ModuleInfo(key: "rope") var rope: RoPE

    public init(config: TextConfig, layerIdx: Int) {
        self.config = config
        self.layerIdx = layerIdx
        self.hiddenSize = config.hiddenSize
        self.numHeads = config.numAttentionHeads
        self.numKvHeads = config.numKeyValueHeads
        self.headDim = config.headDim
        self.scale = pow(Float(headDim), -0.5)

        self._qProj.wrappedValue = Linear(hiddenSize, numHeads * headDim, bias: false)
        self._kProj.wrappedValue = Linear(hiddenSize, numKvHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(hiddenSize, numKvHeads * headDim, bias: false)
        self._oProj.wrappedValue = Linear(numHeads * headDim, hiddenSize, bias: false)

        // Q/K RMSNorm applied per-head
        self._qNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        self._kNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)

        self._rope.wrappedValue = RoPE(dimensions: headDim, traditional: false, base: config.ropeTheta)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, cache: KVCacheSimple? = nil) -> MLXArray {
        let B = hiddenStates.shape[0]
        let L = hiddenStates.shape[1]

        var queries = qProj(hiddenStates)
        var keys = kProj(hiddenStates)
        var values = vProj(hiddenStates)

        // Reshape to per-head: [B, L, num_heads, head_dim]
        queries = queries.reshaped([B, L, numHeads, headDim])
        keys = keys.reshaped([B, L, numKvHeads, headDim])
        values = values.reshaped([B, L, numKvHeads, headDim])

        // Apply Q/K RMSNorm BEFORE RoPE
        queries = qNorm(queries)
        keys = kNorm(keys)

        // Transpose for attention: [B, num_heads, L, head_dim]
        queries = queries.transposed(0, 2, 1, 3)
        keys = keys.transposed(0, 2, 1, 3)
        values = values.transposed(0, 2, 1, 3)

        // Apply RoPE
        let offset = cache?.offset ?? 0
        queries = rope(queries, offset: offset)
        keys = rope(keys, offset: offset)

        // Update cache
        if let cache = cache {
            (keys, values) = cache.update(keys: keys, values: values)
        }

        // Create causal mask
        let queryLen = queries.shape[2]
        let mask = createAdditiveCausalMask(N: queryLen, offset: offset).asType(queries.dtype)

        // Scaled dot product attention
        let output = MLXFast.scaledDotProductAttention(
            queries: queries,
            keys: keys,
            values: values,
            scale: scale,
            mask: mask
        )

        // Reshape back: [B, L, num_heads * head_dim]
        let attnOutput = output.transposed(0, 2, 1, 3).reshaped([B, queryLen, numHeads * headDim])
        return oProj(attnOutput)
    }

    private func createAdditiveCausalMask(N: Int, offset: Int) -> MLXArray {
        let rinds = MLXArray(0..<(offset + N))
        let linds = offset > 0 ? MLXArray(offset..<(offset + N)) : rinds
        let lindsBroadcast = linds.reshaped([-1, 1])
        let rindsBroadcast = rinds.reshaped([1, -1])
        let mask = lindsBroadcast .< rindsBroadcast
        return mask.asType(.float32) * -1e9
    }
}

// MARK: - Text MLP

/// MLP for text decoder with SwiGLU activation.
public class TextMLP: Module {
    let hiddenSize: Int
    let intermediateSize: Int

    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear

    public init(config: TextConfig) {
        self.hiddenSize = config.hiddenSize
        self.intermediateSize = config.intermediateSize

        self._gateProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._upProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._downProj.wrappedValue = Linear(intermediateSize, hiddenSize, bias: false)
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return downProj(silu(gateProj(x)) * upProj(x))
    }
}

// MARK: - Text Decoder Layer

/// A single transformer decoder layer with RMSNorm pre-norm.
public class TextDecoderLayer: Module {
    let hiddenSize: Int

    @ModuleInfo(key: "self_attn") var selfAttn: TextAttention
    @ModuleInfo(key: "mlp") var mlp: TextMLP
    @ModuleInfo(key: "input_layernorm") var inputLayernorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayernorm: RMSNorm

    public init(config: TextConfig, layerIdx: Int) {
        self.hiddenSize = config.hiddenSize

        self._selfAttn.wrappedValue = TextAttention(config: config, layerIdx: layerIdx)
        self._mlp.wrappedValue = TextMLP(config: config)
        self._inputLayernorm.wrappedValue = RMSNorm(dimensions: hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayernorm.wrappedValue = RMSNorm(dimensions: hiddenSize, eps: config.rmsNormEps)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, cache: KVCacheSimple? = nil) -> MLXArray {
        var residual = hiddenStates
        var h = inputLayernorm(hiddenStates)
        h = selfAttn(h, cache: cache)
        h = residual + h

        residual = h
        h = postAttentionLayernorm(h)
        h = mlp(h)
        h = residual + h

        return h
    }
}

// MARK: - Text Model

/// Text decoder model (Qwen3-based).
public class TextModel: Module {
    let config: TextConfig
    let vocabSize: Int
    let numHiddenLayers: Int

    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo(key: "layers") var layers: [TextDecoderLayer]
    @ModuleInfo(key: "norm") var norm: RMSNorm

    public init(config: TextConfig) {
        self.config = config
        self.vocabSize = config.vocabSize
        self.numHiddenLayers = config.numHiddenLayers

        self._embedTokens.wrappedValue = Embedding(embeddingCount: vocabSize, dimensions: config.hiddenSize)
        self._layers.wrappedValue = (0..<numHiddenLayers).map { i in
            TextDecoderLayer(config: config, layerIdx: i)
        }
        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    public func callAsFunction(_ inputIds: MLXArray, cache: [KVCacheSimple]? = nil) -> MLXArray {
        var hiddenStates = embedTokens(inputIds)

        for (i, layer) in layers.enumerated() {
            let layerCache = cache?[i]
            hiddenStates = layer(hiddenStates, cache: layerCache)
        }

        hiddenStates = norm(hiddenStates)
        return hiddenStates
    }
}
