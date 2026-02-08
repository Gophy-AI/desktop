//
//  Qwen3ASREncoderLayers.swift
//  MLXAudioSTT
//
// Qwen3 ASR audio encoder layer implementations.
//

import Foundation
import MLX
import MLXNN

// MARK: - Sinusoidal Position Embedding

/// Sinusoidal position embeddings for the audio encoder.
public class SinusoidalPositionEmbedding: Module {
    private let positionalEmbedding: MLXArray

    public init(length: Int, channels: Int, maxTimescale: Float = 10000.0) {
        precondition(channels % 2 == 0, "SinusoidalPositionEmbedding needs even channels input")

        let logTimescaleIncrement = log(maxTimescale) / Float(channels / 2 - 1)
        let invTimescales = MLX.exp(-logTimescaleIncrement * MLXArray(0..<channels / 2).asType(.float32))
        let positions = MLXArray(0..<length).asType(.float32).reshaped([-1, 1])
        let scaledTime = positions * invTimescales.reshaped([1, -1])

        self.positionalEmbedding = MLX.concatenated([MLX.sin(scaledTime), MLX.cos(scaledTime)], axis: 1)
    }

    public func callAsFunction(_ seqlen: Int) -> MLXArray {
        return positionalEmbedding[0..<seqlen, 0...]
    }
}

// MARK: - Audio Attention

/// Multi-headed attention for audio encoder.
public class AudioAttention: Module {
    let embedDim: Int
    let numHeads: Int
    let headDim: Int
    let scaling: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    public init(config: AudioEncoderConfig) {
        self.embedDim = config.dModel
        self.numHeads = config.encoderAttentionHeads
        self.headDim = embedDim / numHeads
        self.scaling = pow(Float(headDim), -0.5)

        precondition(headDim * numHeads == embedDim,
                     "embed_dim must be divisible by num_heads (got embed_dim: \(embedDim) and num_heads: \(numHeads))")

        self._qProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        self._kProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        self._vProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        self._outProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        let bsz = hiddenStates.shape[0]
        let seqLen = hiddenStates.shape[1]

        var queryStates = qProj(hiddenStates) * scaling
        var keyStates = kProj(hiddenStates)
        var valueStates = vProj(hiddenStates)

        // Reshape to (bsz, numHeads, seqLen, headDim)
        queryStates = queryStates.reshaped([bsz, seqLen, numHeads, headDim]).transposed(0, 2, 1, 3)
        keyStates = keyStates.reshaped([bsz, seqLen, numHeads, headDim]).transposed(0, 2, 1, 3)
        valueStates = valueStates.reshaped([bsz, seqLen, numHeads, headDim]).transposed(0, 2, 1, 3)

        let attnOutput = MLXFast.scaledDotProductAttention(
            queries: queryStates,
            keys: keyStates,
            values: valueStates,
            scale: 1.0,
            mask: mask
        )

        // Reshape back to (bsz, seqLen, embedDim)
        let output = attnOutput.transposed(0, 2, 1, 3).reshaped([bsz, seqLen, embedDim])

        return outProj(output)
    }
}

// MARK: - Audio Encoder Layer

/// A single transformer encoder layer for audio with SwiGLU MLP.
public class AudioEncoderLayer: Module {
    let embedDim: Int

    @ModuleInfo(key: "self_attn") var selfAttn: AudioAttention
    @ModuleInfo(key: "self_attn_layer_norm") var selfAttnLayerNorm: LayerNorm
    @ModuleInfo(key: "fc1") var fc1: Linear
    @ModuleInfo(key: "fc2") var fc2: Linear
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: LayerNorm

    public init(config: AudioEncoderConfig) {
        self.embedDim = config.dModel

        self._selfAttn.wrappedValue = AudioAttention(config: config)
        self._selfAttnLayerNorm.wrappedValue = LayerNorm(dimensions: embedDim)
        self._fc1.wrappedValue = Linear(embedDim, config.encoderFfnDim)
        self._fc2.wrappedValue = Linear(config.encoderFfnDim, embedDim)
        self._finalLayerNorm.wrappedValue = LayerNorm(dimensions: embedDim)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        var residual = hiddenStates
        var h = selfAttnLayerNorm(hiddenStates)
        h = selfAttn(h, mask: mask)
        h = residual + h

        residual = h
        h = finalLayerNorm(h)
        h = gelu(fc1(h))
        h = fc2(h)
        h = residual + h

        return h
    }
}
