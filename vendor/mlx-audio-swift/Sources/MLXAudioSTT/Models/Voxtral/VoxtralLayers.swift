//
//  VoxtralLayers.swift
//  MLXAudioSTT
//
// Voxtral encoder layers and multimodal projector

import Foundation
import MLX
import MLXNN

// MARK: - Voxtral Attention

/// Voxtral attention layer for audio encoding.
public class VoxtralAttention: Module {
    let embedDim: Int
    let numHeads: Int
    let headDim: Int
    let scaling: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    public init(config: VoxtralAudioConfig) {
        self.embedDim = config.dModel
        self.numHeads = config.encoderAttentionHeads
        self.headDim = embedDim / numHeads
        self.scaling = pow(Float(headDim), -0.5)

        self._qProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        self._kProj.wrappedValue = Linear(embedDim, embedDim, bias: false)
        self._vProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
        self._outProj.wrappedValue = Linear(embedDim, embedDim, bias: true)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        let (bsz, tgtLen, _) = (hiddenStates.shape[0], hiddenStates.shape[1], hiddenStates.shape[2])

        var queryStates = qProj(hiddenStates) * scaling
        var keyStates = kProj(hiddenStates)
        var valueStates = vProj(hiddenStates)

        // Reshape to (bsz, numHeads, tgtLen, headDim)
        queryStates = queryStates.reshaped([bsz, tgtLen, numHeads, headDim]).transposed(0, 2, 1, 3)
        keyStates = keyStates.reshaped([bsz, tgtLen, numHeads, headDim]).transposed(0, 2, 1, 3)
        valueStates = valueStates.reshaped([bsz, tgtLen, numHeads, headDim]).transposed(0, 2, 1, 3)

        // Scaled dot product attention with scale=1.0 (scaling already applied to queries)
        let attnOutput = MLXFast.scaledDotProductAttention(
            queries: queryStates,
            keys: keyStates,
            values: valueStates,
            scale: 1.0,
            mask: mask
        )

        // Reshape back to (bsz, tgtLen, embedDim)
        let output = attnOutput.transposed(0, 2, 1, 3).reshaped([bsz, tgtLen, embedDim])

        return outProj(output)
    }
}

// MARK: - Voxtral Encoder Layer

/// Voxtral encoder layer with pre-norm architecture.
public class VoxtralEncoderLayer: Module {
    let embedDim: Int

    @ModuleInfo(key: "self_attn") var selfAttn: VoxtralAttention
    @ModuleInfo(key: "self_attn_layer_norm") var selfAttnLayerNorm: LayerNorm
    @ModuleInfo(key: "fc1") var fc1: Linear
    @ModuleInfo(key: "fc2") var fc2: Linear
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: LayerNorm

    public init(config: VoxtralAudioConfig) {
        self.embedDim = config.dModel

        self._selfAttn.wrappedValue = VoxtralAttention(config: config)
        self._selfAttnLayerNorm.wrappedValue = LayerNorm(dimensions: embedDim)
        self._fc1.wrappedValue = Linear(embedDim, config.encoderFfnDim)
        self._fc2.wrappedValue = Linear(config.encoderFfnDim, embedDim)
        self._finalLayerNorm.wrappedValue = LayerNorm(dimensions: embedDim)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        // Pre-norm self-attention
        var residual = hiddenStates
        var h = selfAttnLayerNorm(hiddenStates)
        h = selfAttn(h, mask: mask)
        h = residual + h

        // Pre-norm FFN
        residual = h
        h = finalLayerNorm(h)
        h = gelu(fc1(h))
        h = fc2(h)
        h = residual + h

        return h
    }
}

// MARK: - Voxtral Encoder

/// Voxtral audio encoder with Conv1d frontend and transformer layers.
public class VoxtralEncoder: Module {
    let config: VoxtralAudioConfig
    let numMelBins: Int
    let maxSourcePositions: Int
    let embedScale: Float

    @ModuleInfo(key: "conv1") var conv1: Conv1d
    @ModuleInfo(key: "conv2") var conv2: Conv1d
    @ModuleInfo(key: "embed_positions") var embedPositions: Embedding
    @ModuleInfo(key: "layers") var layers: [VoxtralEncoderLayer]
    @ModuleInfo(key: "layer_norm") var layerNorm: LayerNorm

    public init(config: VoxtralAudioConfig) {
        self.config = config
        self.numMelBins = config.numMelBins
        self.maxSourcePositions = config.maxSourcePositions

        let embedDim = config.dModel
        self.embedScale = config.scaleEmbedding ? sqrt(Float(embedDim)) : 1.0

        // Conv1d frontend: first conv with stride 1, second with stride 2 for downsampling
        self._conv1.wrappedValue = Conv1d(
            inputChannels: numMelBins,
            outputChannels: embedDim,
            kernelSize: 3,
            padding: 1
        )
        self._conv2.wrappedValue = Conv1d(
            inputChannels: embedDim,
            outputChannels: embedDim,
            kernelSize: 3,
            stride: 2,
            padding: 1
        )

        // Positional embeddings
        self._embedPositions.wrappedValue = Embedding(embeddingCount: maxSourcePositions, dimensions: embedDim)

        // Encoder layers
        var encoderLayers: [VoxtralEncoderLayer] = []
        for _ in 0..<config.encoderLayers {
            encoderLayers.append(VoxtralEncoderLayer(config: config))
        }
        self._layers.wrappedValue = encoderLayers

        // Final layer norm
        self._layerNorm.wrappedValue = LayerNorm(dimensions: embedDim)
    }

    public func callAsFunction(_ inputFeatures: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        // Conv1d frontend with GELU activations
        var hiddenStates = gelu(conv1(inputFeatures))
        hiddenStates = gelu(conv2(hiddenStates))

        // Add positional embeddings
        let embedPos = embedPositions.weight
        hiddenStates = (hiddenStates + embedPos).asType(hiddenStates.dtype)

        // Pass through encoder layers
        for layer in layers {
            hiddenStates = layer(hiddenStates, mask: mask)
        }

        // Final layer norm
        return layerNorm(hiddenStates)
    }
}

// MARK: - Multimodal Projector

/// Multimodal projector mapping audio features to LM token space.
public class VoxtralMultiModalProjector: Module {
    @ModuleInfo(key: "linear_1") var linear1: Linear
    @ModuleInfo(key: "linear_2") var linear2: Linear

    public init(config: VoxtralModelConfig) {
        self._linear1.wrappedValue = Linear(
            config.audioConfig.intermediateSize,
            config.textConfig.hiddenSize,
            bias: false
        )
        self._linear2.wrappedValue = Linear(
            config.textConfig.hiddenSize,
            config.textConfig.hiddenSize,
            bias: false
        )
    }

    public func callAsFunction(_ audioFeatures: MLXArray) -> MLXArray {
        var hiddenStates = linear1(audioFeatures)
        hiddenStates = gelu(hiddenStates)
        hiddenStates = linear2(hiddenStates)
        return hiddenStates
    }
}
