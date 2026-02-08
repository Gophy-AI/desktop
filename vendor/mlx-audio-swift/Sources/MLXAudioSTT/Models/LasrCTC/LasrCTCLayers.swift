//
//  LasrCTCLayers.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation
import MLX
import MLXNN

// MARK: - Helper Functions

private func rotateHalf(_ x: MLXArray) -> MLXArray {
    let halfDim = x.shape[x.ndim - 1] / 2
    let x1 = x[.ellipsis, 0..<halfDim]
    let x2 = x[.ellipsis, halfDim...]
    return concatenated([-x2, x1], axis: -1)
}

private func applyRotaryPosEmb(
    q: MLXArray,
    k: MLXArray,
    cos: MLXArray,
    sin: MLXArray
) -> (MLXArray, MLXArray) {
    let qEmbed = (q * cos) + (rotateHalf(q) * sin)
    let kEmbed = (k * cos) + (rotateHalf(k) * sin)
    return (qEmbed, kEmbed)
}

// MARK: - Rotary Position Embedding

/// RoPE (Rotary Position Embeddings) for LASR encoder.
public class LasrEncoderRotaryEmbedding: Module {
    let dim: Int
    let base: Float

    public init(config: LasrEncoderConfig) {
        self.dim = config.hiddenSize / config.numAttentionHeads
        self.base = config.ropeTheta
        super.init()
    }

    public func callAsFunction(_ x: MLXArray, offset: Int = 0) -> (MLXArray, MLXArray) {
        // x shape: [batch, seq_len, num_heads, head_dim]
        let seqLen = x.shape[1]

        // Create position indices
        let indices = MLXArray(offset..<(offset + seqLen)).asType(.float32)

        // Compute inverse frequencies
        let dimRange = MLXArray(stride(from: 0, to: dim, by: 2).map { Float($0) })
        let invFreq = 1.0 / pow(base, dimRange / Float(dim))

        // Compute angles [seq_len, dim/2]
        let args = indices.expandedDimensions(axis: 1) * invFreq.expandedDimensions(axis: 0)

        // Repeat for cos/sin to match dim [seq_len, dim]
        let argsRepeated = concatenated([args, args], axis: -1)

        let cos = MLX.cos(argsRepeated)
        let sin = MLX.sin(argsRepeated)

        // Reshape to broadcast: [1, seq_len, 1, dim]
        let cosReshaped = cos.expandedDimensions(axes: [0, 2])
        let sinReshaped = sin.expandedDimensions(axes: [0, 2])

        return (cosReshaped, sinReshaped)
    }
}

// MARK: - Subsampling

/// Subsampling module that performs 4x downsampling using Conv1d layers.
public class LasrEncoderSubsampling: Module {
    @ModuleInfo(key: "dense_0") var dense0: Linear
    @ModuleInfo(key: "conv_0") var conv0: Conv1d
    @ModuleInfo(key: "conv_1") var conv1: Conv1d
    @ModuleInfo(key: "dense_1") var dense1: Linear

    public init(config: LasrEncoderConfig) {
        self._dense0.wrappedValue = Linear(
            config.numMelBins,
            config.hiddenSize
        )
        self._conv0.wrappedValue = Conv1d(
            inputChannels: config.hiddenSize,
            outputChannels: config.hiddenSize,
            kernelSize: config.subsamplingConvKernelSize,
            stride: config.subsamplingConvStride,
            padding: 0
        )
        self._conv1.wrappedValue = Conv1d(
            inputChannels: config.hiddenSize,
            outputChannels: config.subsamplingConvChannels,
            kernelSize: config.subsamplingConvKernelSize,
            stride: config.subsamplingConvStride,
            padding: 0
        )
        self._dense1.wrappedValue = Linear(
            config.subsamplingConvChannels,
            config.hiddenSize
        )
        super.init()
    }

    public func callAsFunction(_ inputFeatures: MLXArray) -> MLXArray {
        var hiddenStates = relu(dense0(inputFeatures))
        hiddenStates = relu(conv0(hiddenStates))
        hiddenStates = relu(conv1(hiddenStates))
        return dense1(hiddenStates)
    }
}

// MARK: - Attention

/// Multi-head attention with RoPE and GQA support.
public class LasrEncoderAttention: Module {
    let config: LasrEncoderConfig
    let headDim: Int
    let numHeads: Int
    let numKeyValueHeads: Int
    let numKeyValueGroups: Int
    let scaling: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    public init(config: LasrEncoderConfig) {
        self.config = config
        self.headDim = config.hiddenSize / config.numAttentionHeads
        self.numHeads = config.numAttentionHeads
        self.numKeyValueHeads = config.numKeyValueHeads
        self.numKeyValueGroups = numHeads / numKeyValueHeads
        self.scaling = pow(Float(headDim), -0.5)

        self._qProj.wrappedValue = Linear(
            config.hiddenSize,
            numHeads * headDim,
            bias: config.attentionBias
        )
        self._kProj.wrappedValue = Linear(
            config.hiddenSize,
            numKeyValueHeads * headDim,
            bias: config.attentionBias
        )
        self._vProj.wrappedValue = Linear(
            config.hiddenSize,
            numKeyValueHeads * headDim,
            bias: config.attentionBias
        )
        self._oProj.wrappedValue = Linear(
            numHeads * headDim,
            config.hiddenSize,
            bias: config.attentionBias
        )
        super.init()
    }

    public func callAsFunction(
        _ hiddenStates: MLXArray,
        positionEmbeddings: (MLXArray, MLXArray)? = nil,
        mask: MLXArray? = nil
    ) -> MLXArray {
        let B = hiddenStates.shape[0]
        let L = hiddenStates.shape[1]

        var q = qProj(hiddenStates)
        var k = kProj(hiddenStates)
        var v = vProj(hiddenStates)

        q = q.reshaped([B, L, numHeads, headDim])
        k = k.reshaped([B, L, numKeyValueHeads, headDim])
        v = v.reshaped([B, L, numKeyValueHeads, headDim])

        // Apply RoPE if provided
        if let (cos, sin) = positionEmbeddings {
            (q, k) = applyRotaryPosEmb(q: q, k: k, cos: cos, sin: sin)
        }

        // Transpose to [B, num_heads, L, head_dim]
        q = q.transposed(0, 2, 1, 3)
        k = k.transposed(0, 2, 1, 3)
        v = v.transposed(0, 2, 1, 3)

        // Handle GQA: repeat k and v if needed
        if numKeyValueGroups > 1 {
            k = MLX.repeated(k, count: numKeyValueGroups, axis: 1)
            v = MLX.repeated(v, count: numKeyValueGroups, axis: 1)
        }

        // Scaled dot-product attention
        var w = matmul(q, k.transposed(0, 1, 3, 2)) * scaling
        if let mask = mask {
            w = w + mask
        }
        w = softmax(w, axis: -1)
        var o = matmul(w, v)

        // Transpose back and reshape
        o = o.transposed(0, 2, 1, 3).reshaped([B, L, -1])
        return oProj(o)
    }
}

// MARK: - Convolution Module

/// Conformer-style convolution module with GLU and depthwise convolution.
public class LasrEncoderConvolutionModule: Module {
    let kernelSize: Int
    let activation: (MLXArray) -> MLXArray

    @ModuleInfo(key: "pointwise_conv1") var pointwiseConv1: Conv1d
    @ModuleInfo(key: "depthwise_conv") var depthwiseConv: Conv1d
    @ModuleInfo(key: "norm") var norm: BatchNorm
    @ModuleInfo(key: "pointwise_conv2") var pointwiseConv2: Conv1d

    public init(config: LasrEncoderConfig) {
        let channels = config.hiddenSize
        self.kernelSize = config.convKernelSize
        self.activation = config.hiddenAct == "silu" ? { silu($0) } : { relu($0) }

        self._pointwiseConv1.wrappedValue = Conv1d(
            inputChannels: channels,
            outputChannels: 2 * channels,
            kernelSize: 1,
            stride: 1,
            padding: 0,
            bias: config.convolutionBias
        )
        self._depthwiseConv.wrappedValue = Conv1d(
            inputChannels: channels,
            outputChannels: channels,
            kernelSize: kernelSize,
            stride: 1,
            padding: 0,
            groups: channels,
            bias: config.convolutionBias
        )
        self._norm.wrappedValue = BatchNorm(
            featureCount: config.hiddenSize,
            momentum: config.batchNormMomentum
        )
        self._pointwiseConv2.wrappedValue = Conv1d(
            inputChannels: channels,
            outputChannels: channels,
            kernelSize: 1,
            stride: 1,
            padding: 0,
            bias: config.convolutionBias
        )
        super.init()
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var h = pointwiseConv1(hiddenStates)

        // GLU: split and gate
        let actSize = h.shape[h.ndim - 1] / 2
        let h1 = h[.ellipsis, 0..<actSize]
        let h2 = h[.ellipsis, actSize...]
        h = h1 * sigmoid(h2)

        // Manual padding for depthwise conv
        let padLeft = (kernelSize - 1) / 2
        let padRight = kernelSize - 1 - padLeft
        let widths: [IntOrPair] = [.init((0, 0)), .init((padLeft, padRight)), .init((0, 0))]
        h = padded(h, widths: widths)

        h = depthwiseConv(h)
        h = norm(h)
        h = activation(h)
        h = pointwiseConv2(h)

        return h
    }
}

// MARK: - Feed Forward

/// Feed-forward network module.
public class LasrEncoderFeedForward: Module {
    let activation: (MLXArray) -> MLXArray

    @ModuleInfo(key: "linear1") var linear1: Linear
    @ModuleInfo(key: "linear2") var linear2: Linear

    public init(config: LasrEncoderConfig) {
        self.activation = config.hiddenAct == "silu" ? { silu($0) } : { relu($0) }
        self._linear1.wrappedValue = Linear(
            config.hiddenSize,
            config.intermediateSize,
            bias: config.attentionBias
        )
        self._linear2.wrappedValue = Linear(
            config.intermediateSize,
            config.hiddenSize,
            bias: config.attentionBias
        )
        super.init()
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var h = activation(linear1(hiddenStates))
        h = linear2(h)
        return h
    }
}

// MARK: - Encoder Block

/// LASR encoder block with learned residual weights.
public class LasrEncoderBlock: Module {
    let feedForwardResidualWeights: [Float]
    let convResidualWeights: [Float]

    @ModuleInfo(key: "feed_forward1") var feedForward1: LasrEncoderFeedForward
    @ModuleInfo(key: "self_attn") var selfAttn: LasrEncoderAttention
    @ModuleInfo(key: "conv") var conv: LasrEncoderConvolutionModule
    @ModuleInfo(key: "feed_forward2") var feedForward2: LasrEncoderFeedForward

    @ModuleInfo(key: "norm_feed_forward1") var normFeedForward1: LayerNorm
    @ModuleInfo(key: "norm_self_att") var normSelfAtt: LayerNorm
    @ModuleInfo(key: "norm_conv") var normConv: LayerNorm
    @ModuleInfo(key: "norm_feed_forward2") var normFeedForward2: LayerNorm
    @ModuleInfo(key: "norm_out") var normOut: LayerNorm

    public init(config: LasrEncoderConfig) {
        self.feedForwardResidualWeights = config.feedForwardResidualWeights
        self.convResidualWeights = config.convResidualWeights

        self._feedForward1.wrappedValue = LasrEncoderFeedForward(config: config)
        self._selfAttn.wrappedValue = LasrEncoderAttention(config: config)
        self._conv.wrappedValue = LasrEncoderConvolutionModule(config: config)
        self._feedForward2.wrappedValue = LasrEncoderFeedForward(config: config)

        self._normFeedForward1.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._normSelfAtt.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._normConv.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._normFeedForward2.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        self._normOut.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        super.init()
    }

    public func callAsFunction(
        _ hiddenStates: MLXArray,
        positionEmbeddings: (MLXArray, MLXArray)? = nil,
        mask: MLXArray? = nil
    ) -> MLXArray {
        // FF1 with residual weights
        var residual = hiddenStates
        var h = feedForward1(normFeedForward1(hiddenStates))
        h = feedForwardResidualWeights[0] * residual + feedForwardResidualWeights[1] * h

        // Self attention
        let normalizedH = normSelfAtt(h)
        let attnOutput = selfAttn(normalizedH, positionEmbeddings: positionEmbeddings, mask: mask)
        h = h + attnOutput

        // Convolution with residual weights
        let convOutput = conv(normConv(h))
        h = convResidualWeights[0] * h + convResidualWeights[1] * convOutput

        // FF2 with residual weights
        residual = h
        h = feedForward2(normFeedForward2(h))
        h = feedForwardResidualWeights[0] * residual + feedForwardResidualWeights[1] * h

        return normOut(h)
    }
}

// MARK: - Encoder

/// LASR encoder with subsampling, RoPE, and encoder blocks.
public class LasrEncoder: Module {
    let config: LasrEncoderConfig

    @ModuleInfo(key: "subsampler") var subsampler: LasrEncoderSubsampling
    @ModuleInfo(key: "rotary_emb") var rotaryEmb: LasrEncoderRotaryEmbedding
    @ModuleInfo(key: "layers") var layers: [LasrEncoderBlock]
    @ModuleInfo(key: "out_norm") var outNorm: LayerNorm

    public init(config: LasrEncoderConfig) {
        self.config = config
        self._subsampler.wrappedValue = LasrEncoderSubsampling(config: config)
        self._rotaryEmb.wrappedValue = LasrEncoderRotaryEmbedding(config: config)

        var encoderLayers: [LasrEncoderBlock] = []
        for _ in 0..<config.numHiddenLayers {
            encoderLayers.append(LasrEncoderBlock(config: config))
        }
        self._layers.wrappedValue = encoderLayers

        self._outNorm.wrappedValue = LayerNorm(dimensions: config.hiddenSize, eps: config.layerNormEps)
        super.init()
    }

    public func callAsFunction(
        _ inputFeatures: MLXArray,
        mask: MLXArray? = nil
    ) -> MLXArray {
        var hiddenStates = subsampler(inputFeatures)

        // Compute positional embeddings
        let (cos, sin) = rotaryEmb(hiddenStates)

        for layer in layers {
            hiddenStates = layer(hiddenStates, positionEmbeddings: (cos, sin), mask: mask)
        }

        return outNorm(hiddenStates)
    }
}
