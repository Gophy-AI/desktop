//
//  Wav2VecConvLayers.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation
import MLX
import MLXNN

public class WNConv1d: Module {
    let inChannels: Int
    let outChannels: Int
    let kernelSize: Int
    let stride: Int
    let padding: Int
    let dilation: Int
    let groups: Int
    let hasBias: Bool

    @ModuleInfo var weightG: MLXArray
    @ModuleInfo var weightV: MLXArray
    @ModuleInfo var bias: MLXArray?

    public init(
        inChannels: Int,
        outChannels: Int,
        kernelSize: Int,
        stride: Int = 1,
        padding: Int = 0,
        dilation: Int = 1,
        bias: Bool = true,
        groups: Int = 1
    ) {
        self.inChannels = inChannels
        self.outChannels = outChannels
        self.kernelSize = kernelSize
        self.stride = stride
        self.padding = padding
        self.dilation = dilation
        self.groups = groups
        self.hasBias = bias

        let scale = sqrt(1.0 / Float(inChannels * kernelSize))
        let weightInit = MLXRandom.uniform(
            low: -scale,
            high: scale,
            [outChannels, kernelSize, inChannels / groups]
        )

        let normV = sqrt(sum(pow(weightInit, 2), axes: [1, 2], keepDims: true))
        self._weightG.wrappedValue = normV
        self._weightV.wrappedValue = weightInit / (normV + 1e-12)

        if bias {
            self._bias.wrappedValue = MLXArray.zeros([outChannels])
        }
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let normV = sqrt(sum(pow(weightV, 2), axes: [1, 2], keepDims: true))
        let weight = weightG * weightV / (normV + 1e-12)

        var y = MLX.conv1d(x, weight, stride: stride, padding: padding, dilation: dilation, groups: groups)

        if let bias = bias {
            y = y + bias
        }

        return y
    }
}

public class Wav2Vec2NoLayerNormConvLayer: Module {
    let inConvDim: Int
    let outConvDim: Int

    @ModuleInfo(key: "conv") var conv: Conv1d

    public init(config: Wav2VecModelConfig, layerId: Int) {
        self.inConvDim = layerId > 0 ? config.convDim[layerId - 1] : 1
        self.outConvDim = config.convDim[layerId]

        self._conv.wrappedValue = Conv1d(
            inputChannels: inConvDim,
            outputChannels: outConvDim,
            kernelSize: config.convKernel[layerId],
            stride: config.convStride[layerId],
            bias: false
        )
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var h = hiddenStates.swappedAxes(-2, -1)
        h = conv(h)
        h = h.swappedAxes(-2, -1)
        h = gelu(h)
        return h
    }
}

public class Wav2Vec2LayerNormConvLayer: Module {
    let inConvDim: Int
    let outConvDim: Int

    @ModuleInfo(key: "conv") var conv: Conv1d
    @ModuleInfo(key: "layer_norm") var layerNorm: LayerNorm

    public init(config: Wav2VecModelConfig, layerId: Int) {
        self.inConvDim = layerId > 0 ? config.convDim[layerId - 1] : 1
        self.outConvDim = config.convDim[layerId]

        self._conv.wrappedValue = Conv1d(
            inputChannels: inConvDim,
            outputChannels: outConvDim,
            kernelSize: config.convKernel[layerId],
            stride: config.convStride[layerId],
            bias: false
        )
        self._layerNorm.wrappedValue = LayerNorm(dimensions: outConvDim)
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var h = hiddenStates.swappedAxes(-2, -1)
        h = conv(h)
        h = layerNorm(h)
        h = h.swappedAxes(-2, -1)
        h = gelu(h)
        return h
    }
}

public class Wav2Vec2GroupNormConvLayer: Module {
    let inConvDim: Int
    let outConvDim: Int

    @ModuleInfo(key: "conv") var conv: WNConv1d
    @ModuleInfo(key: "layer_norm") var layerNorm: GroupNorm

    public init(config: Wav2VecModelConfig, layerId: Int) {
        self.inConvDim = layerId > 0 ? config.convDim[layerId - 1] : 1
        self.outConvDim = config.convDim[layerId]

        self._conv.wrappedValue = WNConv1d(
            inChannels: inConvDim,
            outChannels: outConvDim,
            kernelSize: config.convKernel[layerId],
            stride: config.convStride[layerId],
            bias: false
        )

        self._layerNorm.wrappedValue = GroupNorm(
            groupCount: outConvDim,
            dimensions: outConvDim,
            pytorchCompatible: true
        )
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> MLXArray {
        var h = hiddenStates.swappedAxes(-2, -1)
        h = conv(h)
        h = layerNorm(h)
        h = h.swappedAxes(-2, -1)
        h = gelu(h)
        return h
    }
}

public class Wav2Vec2FeatureEncoder: Module {
    let convLayers: [Module]

    public init(config: Wav2VecModelConfig) {
        var layers: [Module] = []

        if config.featExtractNorm == "group" {
            layers.append(Wav2Vec2GroupNormConvLayer(config: config, layerId: 0))
            for i in 1..<7 {
                layers.append(Wav2Vec2NoLayerNormConvLayer(config: config, layerId: i))
            }
        } else if config.featExtractNorm == "layer" {
            for i in 0..<7 {
                layers.append(Wav2Vec2LayerNormConvLayer(config: config, layerId: i))
            }
        } else {
            fatalError("feat_extract_norm must be 'group' or 'layer', got \(config.featExtractNorm)")
        }

        self.convLayers = layers
    }

    public func callAsFunction(_ inputValues: MLXArray) -> MLXArray {
        var hiddenStates = inputValues.expandedDimensions(axis: 1)

        for convLayer in convLayers {
            if let layer = convLayer as? Wav2Vec2GroupNormConvLayer {
                hiddenStates = layer(hiddenStates)
            } else if let layer = convLayer as? Wav2Vec2NoLayerNormConvLayer {
                hiddenStates = layer(hiddenStates)
            } else if let layer = convLayer as? Wav2Vec2LayerNormConvLayer {
                hiddenStates = layer(hiddenStates)
            }
        }

        return hiddenStates
    }
}

public class Wav2Vec2FeatureProjection: Module {
    @ModuleInfo(key: "layer_norm") var layerNorm: LayerNorm
    @ModuleInfo(key: "projection") var projection: Linear
    @ModuleInfo(key: "dropout") var dropout: Dropout

    public init(config: Wav2VecModelConfig) {
        let convDimLast = config.convDim[config.convDim.count - 1]
        self._layerNorm.wrappedValue = LayerNorm(dimensions: convDimLast, eps: config.layerNormEps)
        self._projection.wrappedValue = Linear(convDimLast, config.hiddenSize)
        self._dropout.wrappedValue = Dropout(p: config.featProjDropout)
    }

    public func callAsFunction(_ hiddenStates: MLXArray) -> (MLXArray, MLXArray) {
        let normHiddenStates = layerNorm(hiddenStates)
        let projectedStates = projection(normHiddenStates)
        let droppedStates = dropout(projectedStates)
        return (droppedStates, normHiddenStates)
    }
}
