//
//  LasrCTCConfig.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation

/// Configuration for the LASR encoder.
public struct LasrEncoderConfig: Codable {
    public var hiddenSize: Int
    public var numHiddenLayers: Int
    public var numAttentionHeads: Int
    public var numKeyValueHeads: Int
    public var intermediateSize: Int
    public var hiddenAct: String

    // Convolution
    public var convKernelSize: Int
    public var convolutionBias: Bool

    // Subsampling
    public var numMelBins: Int
    public var subsamplingConvChannels: Int
    public var subsamplingConvKernelSize: Int
    public var subsamplingConvStride: Int

    // Regularization
    public var dropout: Float
    public var attentionDropout: Float
    public var activationDropout: Float
    public var dropoutPositions: Float
    public var layerdrop: Float

    // Normalization
    public var layerNormEps: Float
    public var batchNormMomentum: Float

    // Initializers
    public var initializerRange: Float

    // Positional embeddings
    public var maxPositionEmbeddings: Int
    public var attentionBias: Bool

    // RoPE
    public var ropeTheta: Float
    public var ropeType: String

    // Residual scaling
    public var convResidualWeights: [Float]
    public var feedForwardResidualWeights: [Float]

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case intermediateSize = "intermediate_size"
        case hiddenAct = "hidden_act"
        case convKernelSize = "conv_kernel_size"
        case convolutionBias = "convolution_bias"
        case numMelBins = "num_mel_bins"
        case subsamplingConvChannels = "subsampling_conv_channels"
        case subsamplingConvKernelSize = "subsampling_conv_kernel_size"
        case subsamplingConvStride = "subsampling_conv_stride"
        case dropout
        case attentionDropout = "attention_dropout"
        case activationDropout = "activation_dropout"
        case dropoutPositions = "dropout_positions"
        case layerdrop
        case layerNormEps = "layer_norm_eps"
        case batchNormMomentum = "batch_norm_momentum"
        case initializerRange = "initializer_range"
        case maxPositionEmbeddings = "max_position_embeddings"
        case attentionBias = "attention_bias"
        case ropeTheta = "rope_theta"
        case ropeType = "rope_type"
        case convResidualWeights = "conv_residual_weights"
        case feedForwardResidualWeights = "feed_forward_residual_weights"
    }

    public init(
        hiddenSize: Int = 512,
        numHiddenLayers: Int = 17,
        numAttentionHeads: Int = 8,
        numKeyValueHeads: Int = 8,
        intermediateSize: Int = 2048,
        hiddenAct: String = "silu",
        convKernelSize: Int = 32,
        convolutionBias: Bool = false,
        numMelBins: Int = 128,
        subsamplingConvChannels: Int = 256,
        subsamplingConvKernelSize: Int = 5,
        subsamplingConvStride: Int = 2,
        dropout: Float = 0.1,
        attentionDropout: Float = 0.1,
        activationDropout: Float = 0.1,
        dropoutPositions: Float = 0.0,
        layerdrop: Float = 0.1,
        layerNormEps: Float = 1e-6,
        batchNormMomentum: Float = 0.01,
        initializerRange: Float = 0.02,
        maxPositionEmbeddings: Int = 10000,
        attentionBias: Bool = false,
        ropeTheta: Float = 10000.0,
        ropeType: String = "default",
        convResidualWeights: [Float] = [2.0, 1.0],
        feedForwardResidualWeights: [Float] = [1.5, 0.5]
    ) {
        self.hiddenSize = hiddenSize
        self.numHiddenLayers = numHiddenLayers
        self.numAttentionHeads = numAttentionHeads
        self.numKeyValueHeads = numKeyValueHeads
        self.intermediateSize = intermediateSize
        self.hiddenAct = hiddenAct
        self.convKernelSize = convKernelSize
        self.convolutionBias = convolutionBias
        self.numMelBins = numMelBins
        self.subsamplingConvChannels = subsamplingConvChannels
        self.subsamplingConvKernelSize = subsamplingConvKernelSize
        self.subsamplingConvStride = subsamplingConvStride
        self.dropout = dropout
        self.attentionDropout = attentionDropout
        self.activationDropout = activationDropout
        self.dropoutPositions = dropoutPositions
        self.layerdrop = layerdrop
        self.layerNormEps = layerNormEps
        self.batchNormMomentum = batchNormMomentum
        self.initializerRange = initializerRange
        self.maxPositionEmbeddings = maxPositionEmbeddings
        self.attentionBias = attentionBias
        self.ropeTheta = ropeTheta
        self.ropeType = ropeType
        self.convResidualWeights = convResidualWeights
        self.feedForwardResidualWeights = feedForwardResidualWeights
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 512
        numHiddenLayers = try container.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 17
        numAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 8
        numKeyValueHeads = try container.decodeIfPresent(Int.self, forKey: .numKeyValueHeads) ?? 8
        intermediateSize = try container.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 2048
        hiddenAct = try container.decodeIfPresent(String.self, forKey: .hiddenAct) ?? "silu"
        convKernelSize = try container.decodeIfPresent(Int.self, forKey: .convKernelSize) ?? 32
        convolutionBias = try container.decodeIfPresent(Bool.self, forKey: .convolutionBias) ?? false
        numMelBins = try container.decodeIfPresent(Int.self, forKey: .numMelBins) ?? 128
        subsamplingConvChannels = try container.decodeIfPresent(Int.self, forKey: .subsamplingConvChannels) ?? 256
        subsamplingConvKernelSize = try container.decodeIfPresent(Int.self, forKey: .subsamplingConvKernelSize) ?? 5
        subsamplingConvStride = try container.decodeIfPresent(Int.self, forKey: .subsamplingConvStride) ?? 2
        dropout = try container.decodeIfPresent(Float.self, forKey: .dropout) ?? 0.1
        attentionDropout = try container.decodeIfPresent(Float.self, forKey: .attentionDropout) ?? 0.1
        activationDropout = try container.decodeIfPresent(Float.self, forKey: .activationDropout) ?? 0.1
        dropoutPositions = try container.decodeIfPresent(Float.self, forKey: .dropoutPositions) ?? 0.0
        layerdrop = try container.decodeIfPresent(Float.self, forKey: .layerdrop) ?? 0.1
        layerNormEps = try container.decodeIfPresent(Float.self, forKey: .layerNormEps) ?? 1e-6
        batchNormMomentum = try container.decodeIfPresent(Float.self, forKey: .batchNormMomentum) ?? 0.01
        initializerRange = try container.decodeIfPresent(Float.self, forKey: .initializerRange) ?? 0.02
        maxPositionEmbeddings = try container.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings) ?? 10000
        attentionBias = try container.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 10000.0
        ropeType = try container.decodeIfPresent(String.self, forKey: .ropeType) ?? "default"
        convResidualWeights = try container.decodeIfPresent([Float].self, forKey: .convResidualWeights) ?? [2.0, 1.0]
        feedForwardResidualWeights = try container.decodeIfPresent([Float].self, forKey: .feedForwardResidualWeights) ?? [1.5, 0.5]
    }
}

/// Configuration for the LASR CTC model.
public struct LasrCTCModelConfig: Codable {
    public var vocabSize: Int
    public var encoderConfig: LasrEncoderConfig
    public var ctcLossReduction: String
    public var ctcZeroInfinity: Bool
    public var padTokenId: Int
    public var initializerRange: Float
    public var modelType: String

    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case encoderConfig = "encoder_config"
        case ctcLossReduction = "ctc_loss_reduction"
        case ctcZeroInfinity = "ctc_zero_infinity"
        case padTokenId = "pad_token_id"
        case initializerRange = "initializer_range"
        case modelType = "model_type"
    }

    public init(
        vocabSize: Int = 512,
        encoderConfig: LasrEncoderConfig = LasrEncoderConfig(),
        ctcLossReduction: String = "mean",
        ctcZeroInfinity: Bool = true,
        padTokenId: Int = 0,
        initializerRange: Float = 0.02,
        modelType: String = "lasr_ctc"
    ) {
        self.vocabSize = vocabSize
        self.encoderConfig = encoderConfig
        self.ctcLossReduction = ctcLossReduction
        self.ctcZeroInfinity = ctcZeroInfinity
        self.padTokenId = padTokenId
        self.initializerRange = initializerRange
        self.modelType = modelType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 512
        encoderConfig = try container.decodeIfPresent(LasrEncoderConfig.self, forKey: .encoderConfig) ?? LasrEncoderConfig()
        ctcLossReduction = try container.decodeIfPresent(String.self, forKey: .ctcLossReduction) ?? "mean"
        ctcZeroInfinity = try container.decodeIfPresent(Bool.self, forKey: .ctcZeroInfinity) ?? true
        padTokenId = try container.decodeIfPresent(Int.self, forKey: .padTokenId) ?? 0
        initializerRange = try container.decodeIfPresent(Float.self, forKey: .initializerRange) ?? 0.02
        modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "lasr_ctc"
    }
}
