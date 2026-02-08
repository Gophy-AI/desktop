//
//  Wav2VecEncoder.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation
import MLX
import MLXNN

public class Wav2Vec2SamePadLayer: Module {
    let numPadRemove: Int

    public init(numConvPosEmbeddings: Int) {
        self.numPadRemove = numConvPosEmbeddings % 2 == 0 ? 1 : 0
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        if numPadRemove > 0 {
            return hiddenStates[0..., 0..<(hiddenStates.shape[1] - numPadRemove), 0...]
        }
        return hiddenStates
    }
}

public class Wav2Vec2PositionalConvEmbedding: Module {
    @ModuleInfo(key: "conv") var conv: WNConv1d
    @ModuleInfo(key: "padding") var padding: Wav2Vec2SamePadLayer

    public init(config: Wav2VecModelConfig) {
        self._conv.wrappedValue = WNConv1d(
            inChannels: config.hiddenSize,
            outChannels: config.hiddenSize,
            kernelSize: config.numConvPosEmbeddings,
            padding: config.numConvPosEmbeddings / 2,
            groups: config.numConvPosEmbeddingGroups
        )
        self._padding.wrappedValue = Wav2Vec2SamePadLayer(numConvPosEmbeddings: config.numConvPosEmbeddings)
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var h = conv(hiddenStates)
        h = padding(h)
        h = gelu(h)
        return h
    }
}

public class Wav2Vec2Attention: Module {
    let embedDim: Int
    let numHeads: Int
    let headDim: Int
    let scaling: Float

    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "out_proj") var outProj: Linear

    public init(
        embedDim: Int,
        numHeads: Int,
        dropout: Float = 0.0,
        bias: Bool = true
    ) {
        self.embedDim = embedDim
        self.numHeads = numHeads
        self.headDim = embedDim / numHeads
        self.scaling = pow(Float(headDim), -0.5)

        self._kProj.wrappedValue = Linear(embedDim, embedDim, bias: bias)
        self._vProj.wrappedValue = Linear(embedDim, embedDim, bias: bias)
        self._qProj.wrappedValue = Linear(embedDim, embedDim, bias: bias)
        self._outProj.wrappedValue = Linear(embedDim, embedDim, bias: bias)
    }

    func shape(_ tensor: MLXArray, seqLen: Int, bsz: Int) -> MLXArray {
        return tensor.reshaped(bsz, seqLen, numHeads, headDim).transposed(0, 2, 1, 3)
    }

    public func callAsFunction(
        _ hiddenStates: MLXArray,
        attentionMask: MLXArray? = nil
    ) -> (MLXArray, MLXArray?) {
        let bsz = hiddenStates.shape[0]
        let tgtLen = hiddenStates.shape[1]

        var queryStates = qProj(hiddenStates) * scaling
        let keyStates = shape(kProj(hiddenStates), seqLen: -1, bsz: bsz)
        let valueStates = shape(vProj(hiddenStates), seqLen: -1, bsz: bsz)

        queryStates = shape(queryStates, seqLen: tgtLen, bsz: bsz)

        let attnOutput = MLXFast.scaledDotProductAttention(
            queries: queryStates,
            keys: keyStates,
            values: valueStates,
            scale: 1.0,
            mask: attentionMask
        )

        let output = attnOutput.transposed(0, 2, 1, 3).reshaped(bsz, tgtLen, embedDim)
        return (outProj(output), nil)
    }
}

public class Wav2Vec2FeedForward: Module {
    @ModuleInfo(key: "intermediate_dense") var intermediateDense: Linear
    @ModuleInfo(key: "intermediate_dropout") var intermediateDropout: Dropout
    @ModuleInfo(key: "output_dense") var outputDense: Linear
    @ModuleInfo(key: "output_dropout") var outputDropout: Dropout

    public init(config: Wav2VecModelConfig) {
        self._intermediateDense.wrappedValue = Linear(config.hiddenSize, config.intermediateSize)
        self._intermediateDropout.wrappedValue = Dropout(p: config.activationDropout)
        self._outputDense.wrappedValue = Linear(config.intermediateSize, config.hiddenSize)
        self._outputDropout.wrappedValue = Dropout(p: config.hiddenDropout)
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var h = intermediateDense(hiddenStates)
        h = gelu(h)
        h = intermediateDropout(h)
        h = outputDense(h)
        h = outputDropout(h)
        return h
    }
}

public class Wav2Vec2EncoderLayer: Module {
    @ModuleInfo(key: "attention") var attention: Wav2Vec2Attention
    @ModuleInfo(key: "dropout") var dropout: Dropout
    @ModuleInfo(key: "layer_norm") var layerNorm: LayerNorm
    @ModuleInfo(key: "feed_forward") var feedForward: Wav2Vec2FeedForward
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: LayerNorm

    public init(config: Wav2VecModelConfig) {
        self._attention.wrappedValue = Wav2Vec2Attention(
            embedDim: config.hiddenSize,
            numHeads: config.numAttentionHeads,
            dropout: config.attentionDropout,
            bias: true
        )
        self._dropout.wrappedValue = Dropout(p: config.hiddenDropout)
        self._layerNorm.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._feedForward.wrappedValue = Wav2Vec2FeedForward(config: config)
        self._finalLayerNorm.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil) -> MLXArray {
        let attnResidual = hiddenStates
        let (attnOut, _) = attention(hiddenStates, attentionMask: attentionMask)
        var h = dropout(attnOut)
        h = attnResidual + h
        h = layerNorm(h)
        h = h + feedForward(h)
        h = finalLayerNorm(h)
        return h
    }
}

public class Wav2Vec2EncoderLayerStableLayerNorm: Module {
    @ModuleInfo(key: "attention") var attention: Wav2Vec2Attention
    @ModuleInfo(key: "dropout") var dropout: Dropout
    @ModuleInfo(key: "layer_norm") var layerNorm: LayerNorm
    @ModuleInfo(key: "feed_forward") var feedForward: Wav2Vec2FeedForward
    @ModuleInfo(key: "final_layer_norm") var finalLayerNorm: LayerNorm

    public init(config: Wav2VecModelConfig) {
        self._attention.wrappedValue = Wav2Vec2Attention(
            embedDim: config.hiddenSize,
            numHeads: config.numAttentionHeads,
            dropout: config.attentionDropout,
            bias: true
        )
        self._dropout.wrappedValue = Dropout(p: config.hiddenDropout)
        self._layerNorm.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._feedForward.wrappedValue = Wav2Vec2FeedForward(config: config)
        self._finalLayerNorm.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
    }

    public func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil) -> MLXArray {
        let attnResidual = hiddenStates
        let (attnOut, _) = attention(layerNorm(hiddenStates), attentionMask: attentionMask)
        var h = dropout(attnOut)
        h = attnResidual + h
        h = h + feedForward(finalLayerNorm(h))
        return h
    }
}

public struct Wav2Vec2BaseModelOutput {
    public let lastHiddenState: MLXArray
    public let extractFeatures: MLXArray?
    public let hiddenStates: [MLXArray]?

    public init(lastHiddenState: MLXArray, extractFeatures: MLXArray? = nil, hiddenStates: [MLXArray]? = nil) {
        self.lastHiddenState = lastHiddenState
        self.extractFeatures = extractFeatures
        self.hiddenStates = hiddenStates
    }
}

public class Wav2Vec2Encoder: Module {
    @ModuleInfo(key: "pos_conv_embed") var posConvEmbed: Wav2Vec2PositionalConvEmbedding
    @ModuleInfo(key: "layer_norm") var layerNorm: LayerNorm
    @ModuleInfo(key: "dropout") var dropout: Dropout
    let layers: [Wav2Vec2EncoderLayer]

    public init(config: Wav2VecModelConfig) {
        self._posConvEmbed.wrappedValue = Wav2Vec2PositionalConvEmbedding(config: config)
        self._layerNorm.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._dropout.wrappedValue = Dropout(p: config.hiddenDropout)

        var encoderLayers: [Wav2Vec2EncoderLayer] = []
        for _ in 0..<config.numHiddenLayers {
            encoderLayers.append(Wav2Vec2EncoderLayer(config: config))
        }
        self.layers = encoderLayers
    }

    public func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil) -> Wav2Vec2BaseModelOutput {
        let positionEmbeddings = posConvEmbed(hiddenStates)
        var h = hiddenStates + positionEmbeddings
        h = layerNorm(h)
        h = dropout(h)

        for layer in layers {
            h = layer(h, attentionMask: attentionMask)
        }

        return Wav2Vec2BaseModelOutput(lastHiddenState: h)
    }
}

public class Wav2Vec2EncoderStableLayerNorm: Module {
    @ModuleInfo(key: "pos_conv_embed") var posConvEmbed: Wav2Vec2PositionalConvEmbedding
    @ModuleInfo(key: "layer_norm") var layerNorm: LayerNorm
    @ModuleInfo(key: "dropout") var dropout: Dropout
    let layers: [Wav2Vec2EncoderLayerStableLayerNorm]

    public init(config: Wav2VecModelConfig) {
        self._posConvEmbed.wrappedValue = Wav2Vec2PositionalConvEmbedding(config: config)
        self._layerNorm.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._dropout.wrappedValue = Dropout(p: config.hiddenDropout)

        var encoderLayers: [Wav2Vec2EncoderLayerStableLayerNorm] = []
        for _ in 0..<config.numHiddenLayers {
            encoderLayers.append(Wav2Vec2EncoderLayerStableLayerNorm(config: config))
        }
        self.layers = encoderLayers
    }

    public func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil) -> Wav2Vec2BaseModelOutput {
        let positionEmbeddings = posConvEmbed(hiddenStates)
        var h = hiddenStates + positionEmbeddings
        h = dropout(h)

        for layer in layers {
            h = layer(h, attentionMask: attentionMask)
        }

        h = layerNorm(h)

        return Wav2Vec2BaseModelOutput(lastHiddenState: h)
    }
}
