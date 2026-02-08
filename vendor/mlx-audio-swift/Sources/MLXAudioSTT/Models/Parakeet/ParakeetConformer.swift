//
//  ParakeetConformer.swift
//  MLXAudioSTT
//
//  Conformer encoder for Parakeet models.
//

import Foundation
import MLX
import MLXNN

// MARK: - Feed-Forward Network

/// Feed-forward network with SiLU activation (Macaron-style half-step FFN in Conformer).
public class FeedForward: Module {
    @ModuleInfo(key: "linear1") var linear1: Linear
    @ModuleInfo(key: "linear2") var linear2: Linear
    let activation: SiLU

    public init(dModel: Int, dFf: Int, useBias: Bool = true) {
        self._linear1.wrappedValue = Linear(dModel, dFf, bias: useBias)
        self._linear2.wrappedValue = Linear(dFf, dModel, bias: useBias)
        self.activation = SiLU()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return linear2(activation(linear1(x)))
    }
}

// MARK: - Convolution Module

/// Conformer convolution module with GLU and depthwise convolution.
public class Convolution: Module {
    @ModuleInfo(key: "pointwise_conv1") var pointwiseConv1: Conv1d
    @ModuleInfo(key: "depthwise_conv") var depthwiseConv: Conv1d
    @ModuleInfo(key: "batch_norm") var batchNorm: BatchNorm
    @ModuleInfo(key: "pointwise_conv2") var pointwiseConv2: Conv1d
    let activation: SiLU

    public init(args: ConformerArgs) {
        precondition((args.convKernelSize - 1) % 2 == 0)

        self._pointwiseConv1.wrappedValue = Conv1d(
            inputChannels: args.dModel,
            outputChannels: args.dModel * 2,
            kernelSize: 1,
            stride: 1,
            padding: 0,
            bias: args.useBias
        )
        self._depthwiseConv.wrappedValue = Conv1d(
            inputChannels: args.dModel,
            outputChannels: args.dModel,
            kernelSize: args.convKernelSize,
            stride: 1,
            padding: (args.convKernelSize - 1) / 2,
            groups: args.dModel,
            bias: args.useBias
        )
        self._batchNorm.wrappedValue = BatchNorm(featureCount: args.dModel, eps: 1e-5)
        self._pointwiseConv2.wrappedValue = Conv1d(
            inputChannels: args.dModel,
            outputChannels: args.dModel,
            kernelSize: 1,
            stride: 1,
            padding: 0,
            bias: args.useBias
        )
        self.activation = SiLU()
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var result = pointwiseConv1(x)

        // GLU activation (split and multiply)
        let halfChannels = result.dim(2) / 2
        let gate = result[0..., 0..., 0..<halfChannels]
        let value = result[0..., 0..., halfChannels...]
        result = gate * sigmoid(value)

        result = depthwiseConv(result)
        result = batchNorm(result)
        result = activation(result)
        result = pointwiseConv2(result)

        return result
    }
}

// MARK: - Conformer Block

/// Conformer block with Macaron-style half-step FFN.
///
/// Architecture: 0.5*FFN + Attention + Conv + 0.5*FFN + LayerNorm
public class ConformerBlock: Module {
    @ModuleInfo(key: "norm_feed_forward1") var normFeedForward1: LayerNorm
    @ModuleInfo(key: "feed_forward1") var feedForward1: FeedForward

    @ModuleInfo(key: "norm_self_att") var normSelfAtt: LayerNorm
    @ModuleInfo(key: "self_attn") var selfAttn: Module

    @ModuleInfo(key: "norm_conv") var normConv: LayerNorm
    @ModuleInfo(key: "conv") var conv: Convolution

    @ModuleInfo(key: "norm_feed_forward2") var normFeedForward2: LayerNorm
    @ModuleInfo(key: "feed_forward2") var feedForward2: FeedForward

    @ModuleInfo(key: "norm_out") var normOut: LayerNorm

    let isRelativeAttention: Bool

    public init(args: ConformerArgs) {
        let ffHiddenDim = args.dModel * args.ffExpansionFactor

        self._normFeedForward1.wrappedValue = LayerNorm(dimensions: args.dModel)
        self._feedForward1.wrappedValue = FeedForward(dModel: args.dModel, dFf: ffHiddenDim, useBias: args.useBias)

        self._normSelfAtt.wrappedValue = LayerNorm(dimensions: args.dModel)

        if args.selfAttentionModel == "rel_pos" {
            self._selfAttn.wrappedValue = RelPositionMultiHeadAttention(
                dModel: args.dModel,
                nHeads: args.nHeads,
                useBias: args.useBias,
                posBiasU: args.posBiasU,
                posBiasV: args.posBiasV
            )
            self.isRelativeAttention = true
        } else {
            self._selfAttn.wrappedValue = MultiHeadAttention(
                dModel: args.dModel,
                nHeads: args.nHeads,
                useBias: args.useBias
            )
            self.isRelativeAttention = false
        }

        self._normConv.wrappedValue = LayerNorm(dimensions: args.dModel)
        self._conv.wrappedValue = Convolution(args: args)

        self._normFeedForward2.wrappedValue = LayerNorm(dimensions: args.dModel)
        self._feedForward2.wrappedValue = FeedForward(dModel: args.dModel, dFf: ffHiddenDim, useBias: args.useBias)

        self._normOut.wrappedValue = LayerNorm(dimensions: args.dModel)
    }

    public func callAsFunction(_ x: MLXArray, posEmb: MLXArray? = nil, mask: MLXArray? = nil) -> MLXArray {
        var result = x

        // Half-step FFN1
        result = result + (0.5 * feedForward1(normFeedForward1(result)))

        // Self-attention
        let xNorm = normSelfAtt(result)
        if isRelativeAttention, let posEmb = posEmb, let attn = selfAttn as? RelPositionMultiHeadAttention {
            result = result + attn(xNorm, pos: posEmb, mask: mask)
        } else if let attn = selfAttn as? MultiHeadAttention {
            result = result + attn(xNorm, mask: mask)
        }

        // Convolution
        result = result + conv(normConv(result))

        // Half-step FFN2
        result = result + (0.5 * feedForward2(normFeedForward2(result)))

        return normOut(result)
    }
}

// MARK: - Depthwise Striding Subsampling

/// Depthwise striding subsampling with Conv2d layers.
public class DwStridingSubsampling: Module {
    let subsamplingFactor: Int
    let convChannels: Int
    let samplingNum: Int
    let stride: Int = 2
    let kernelSize: Int = 3
    let padding: Int = 1

    var convLayers: [Module] = []
    @ModuleInfo(key: "out") var out: Linear

    public init(args: ConformerArgs) {
        precondition(args.subsamplingFactor > 0)
        precondition((args.subsamplingFactor & (args.subsamplingFactor - 1)) == 0)

        self.subsamplingFactor = args.subsamplingFactor
        self.convChannels = args.subsamplingConvChannels
        self.samplingNum = Int(log2(Double(args.subsamplingFactor)))

        var inChannels = 1
        var finalFreqDim = args.featIn
        for _ in 0..<samplingNum {
            finalFreqDim = ((finalFreqDim + 2 * padding - kernelSize) / stride) + 1
            precondition(finalFreqDim >= 1)
        }

        // First conv layer
        convLayers.append(
            Conv2d(
                inputChannels: inChannels,
                outputChannels: convChannels,
                kernelSize: .init((kernelSize, kernelSize)),
                stride: .init((stride, stride)),
                padding: .init((padding, padding))
            )
        )
        convLayers.append(ReLU())
        inChannels = convChannels

        // Subsequent layers (depthwise + pointwise + activation)
        for _ in 0..<(samplingNum - 1) {
            convLayers.append(
                Conv2d(
                    inputChannels: inChannels,
                    outputChannels: inChannels,
                    kernelSize: .init((kernelSize, kernelSize)),
                    stride: .init((stride, stride)),
                    padding: .init((padding, padding)),
                    groups: inChannels
                )
            )
            convLayers.append(
                Conv2d(
                    inputChannels: inChannels,
                    outputChannels: convChannels,
                    kernelSize: .init((1, 1)),
                    stride: .init((1, 1)),
                    padding: .init((0, 0))
                )
            )
            convLayers.append(ReLU())
        }

        self._out.wrappedValue = Linear(convChannels * finalFreqDim, args.dModel)
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var result = x

        // Apply all conv layers
        for layer in convLayers {
            if let conv = layer as? Conv2d {
                result = conv(result)
            } else if let activation = layer as? ReLU {
                result = activation(result)
            }
        }

        // Flatten and project
        let (B, C, T, F) = (result.dim(0), result.dim(1), result.dim(2), result.dim(3))
        result = result.transposed(0, 2, 1, 3).reshaped(B, T, C * F)

        return out(result)
    }
}

// MARK: - Conformer Encoder

/// Conformer encoder with depthwise striding subsampling and relative positional encoding.
public class Conformer: Module {
    @ModuleInfo(key: "subsampling") var subsampling: DwStridingSubsampling
    @ModuleInfo(key: "pos_enc") var posEnc: RelPositionalEncoding
    var layers: [ConformerBlock]

    public init(args: ConformerArgs) {
        self._subsampling.wrappedValue = DwStridingSubsampling(args: args)
        self._posEnc.wrappedValue = RelPositionalEncoding(dModel: args.dModel, maxLen: args.posEmbMaxLen)
        self.layers = (0..<args.nLayers).map { _ in ConformerBlock(args: args) }
    }

    public func callAsFunction(_ x: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        var result = subsampling(x)
        let (resultWithPos, posEmb) = posEnc(result)
        result = resultWithPos

        for layer in layers {
            result = layer(result, posEmb: posEmb, mask: mask)
        }

        return result
    }
}
