//
//  ParakeetConfig.swift
//  MLXAudioSTT
//
//  Parakeet configuration types for NVIDIA NeMo Conformer-based STT models.
//

import Foundation
import MLX
import MLXAudioCore

// MARK: - Conformer Configuration

/// Configuration for the Conformer encoder.
public struct ConformerArgs: Codable, @unchecked Sendable {
    /// Input feature dimension (mel bins after preprocessing)
    public var featIn: Int
    /// Number of conformer layers
    public var nLayers: Int
    /// Model dimension
    public var dModel: Int
    /// Number of attention heads
    public var nHeads: Int
    /// Feed-forward expansion factor
    public var ffExpansionFactor: Int
    /// Subsampling factor (temporal downsampling)
    public var subsamplingFactor: Int
    /// Self-attention model type ("rel_pos" for relative positional)
    public var selfAttentionModel: String
    /// Subsampling type ("dw_striding" for depthwise striding)
    public var subsampling: String
    /// Convolution kernel size
    public var convKernelSize: Int
    /// Subsampling convolution channels
    public var subsamplingConvChannels: Int
    /// Maximum positional encoding length
    public var posEmbMaxLen: Int
    /// Use causal downsampling
    public var causalDownsampling: Bool
    /// Use bias in linear layers
    public var useBias: Bool
    /// Use x-scaling for attention
    public var xscaling: Bool
    /// Positional bias U parameter (learned)
    public var posBiasU: MLXArray?
    /// Positional bias V parameter (learned)
    public var posBiasV: MLXArray?
    /// Subsampling convolution chunking factor
    public var subsamplingConvChunkingFactor: Int

    enum CodingKeys: String, CodingKey {
        case featIn = "feat_in"
        case nLayers = "n_layers"
        case dModel = "d_model"
        case nHeads = "n_heads"
        case ffExpansionFactor = "ff_expansion_factor"
        case subsamplingFactor = "subsampling_factor"
        case selfAttentionModel = "self_attention_model"
        case subsampling
        case convKernelSize = "conv_kernel_size"
        case subsamplingConvChannels = "subsampling_conv_channels"
        case posEmbMaxLen = "pos_emb_max_len"
        case causalDownsampling = "causal_downsampling"
        case useBias = "use_bias"
        case xscaling
        case subsamplingConvChunkingFactor = "subsampling_conv_chunking_factor"
    }

    public init(
        featIn: Int = 80,
        nLayers: Int = 17,
        dModel: Int = 512,
        nHeads: Int = 8,
        ffExpansionFactor: Int = 4,
        subsamplingFactor: Int = 8,
        selfAttentionModel: String = "rel_pos",
        subsampling: String = "dw_striding",
        convKernelSize: Int = 9,
        subsamplingConvChannels: Int = 256,
        posEmbMaxLen: Int = 5000,
        causalDownsampling: Bool = false,
        useBias: Bool = true,
        xscaling: Bool = false,
        posBiasU: MLXArray? = nil,
        posBiasV: MLXArray? = nil,
        subsamplingConvChunkingFactor: Int = 1
    ) {
        self.featIn = featIn
        self.nLayers = nLayers
        self.dModel = dModel
        self.nHeads = nHeads
        self.ffExpansionFactor = ffExpansionFactor
        self.subsamplingFactor = subsamplingFactor
        self.selfAttentionModel = selfAttentionModel
        self.subsampling = subsampling
        self.convKernelSize = convKernelSize
        self.subsamplingConvChannels = subsamplingConvChannels
        self.posEmbMaxLen = posEmbMaxLen
        self.causalDownsampling = causalDownsampling
        self.useBias = useBias
        self.xscaling = xscaling
        self.posBiasU = posBiasU
        self.posBiasV = posBiasV
        self.subsamplingConvChunkingFactor = subsamplingConvChunkingFactor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        featIn = try container.decode(Int.self, forKey: .featIn)
        nLayers = try container.decode(Int.self, forKey: .nLayers)
        dModel = try container.decode(Int.self, forKey: .dModel)
        nHeads = try container.decode(Int.self, forKey: .nHeads)
        ffExpansionFactor = try container.decode(Int.self, forKey: .ffExpansionFactor)
        subsamplingFactor = try container.decode(Int.self, forKey: .subsamplingFactor)
        selfAttentionModel = try container.decodeIfPresent(String.self, forKey: .selfAttentionModel) ?? "rel_pos"
        subsampling = try container.decodeIfPresent(String.self, forKey: .subsampling) ?? "dw_striding"
        convKernelSize = try container.decode(Int.self, forKey: .convKernelSize)
        subsamplingConvChannels = try container.decode(Int.self, forKey: .subsamplingConvChannels)
        posEmbMaxLen = try container.decodeIfPresent(Int.self, forKey: .posEmbMaxLen) ?? 5000
        causalDownsampling = try container.decodeIfPresent(Bool.self, forKey: .causalDownsampling) ?? false
        useBias = try container.decodeIfPresent(Bool.self, forKey: .useBias) ?? true
        xscaling = try container.decodeIfPresent(Bool.self, forKey: .xscaling) ?? false
        posBiasU = nil
        posBiasV = nil
        subsamplingConvChunkingFactor = try container.decodeIfPresent(Int.self, forKey: .subsamplingConvChunkingFactor) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featIn, forKey: .featIn)
        try container.encode(nLayers, forKey: .nLayers)
        try container.encode(dModel, forKey: .dModel)
        try container.encode(nHeads, forKey: .nHeads)
        try container.encode(ffExpansionFactor, forKey: .ffExpansionFactor)
        try container.encode(subsamplingFactor, forKey: .subsamplingFactor)
        try container.encode(selfAttentionModel, forKey: .selfAttentionModel)
        try container.encode(subsampling, forKey: .subsampling)
        try container.encode(convKernelSize, forKey: .convKernelSize)
        try container.encode(subsamplingConvChannels, forKey: .subsamplingConvChannels)
        try container.encode(posEmbMaxLen, forKey: .posEmbMaxLen)
        try container.encode(causalDownsampling, forKey: .causalDownsampling)
        try container.encode(useBias, forKey: .useBias)
        try container.encode(xscaling, forKey: .xscaling)
        try container.encode(subsamplingConvChunkingFactor, forKey: .subsamplingConvChunkingFactor)
    }
}

// MARK: - Prediction Network Configuration

/// Configuration for RNNT/TDT prediction network.
public struct PredictNetworkArgs: Codable, Sendable {
    public var vocabSize: Int
    public var embedDim: Int
    public var hiddenDim: Int
    public var numLayers: Int

    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case embedDim = "embed_dim"
        case hiddenDim = "hidden_dim"
        case numLayers = "num_layers"
    }

    public init(vocabSize: Int, embedDim: Int, hiddenDim: Int, numLayers: Int) {
        self.vocabSize = vocabSize
        self.embedDim = embedDim
        self.hiddenDim = hiddenDim
        self.numLayers = numLayers
    }
}

// MARK: - Joint Network Configuration

/// Configuration for RNNT/TDT joint network.
public struct JointNetworkArgs: Codable, Sendable {
    public var encHidden: Int
    public var predHidden: Int
    public var jointHidden: Int
    public var vocabSize: Int
    public var activation: String

    enum CodingKeys: String, CodingKey {
        case encHidden = "enc_hidden"
        case predHidden = "pred_hidden"
        case jointHidden = "joint_hidden"
        case vocabSize = "vocab_size"
        case activation
    }

    public init(encHidden: Int, predHidden: Int, jointHidden: Int, vocabSize: Int, activation: String = "relu") {
        self.encHidden = encHidden
        self.predHidden = predHidden
        self.jointHidden = jointHidden
        self.vocabSize = vocabSize
        self.activation = activation
    }
}

// MARK: - CTC Decoder Configuration

/// Configuration for CTC decoder head.
public struct ConvASRDecoderArgs: Codable, Sendable {
    public var featIn: Int
    public var numClasses: Int

    enum CodingKeys: String, CodingKey {
        case featIn = "feat_in"
        case numClasses = "num_classes"
    }

    public init(featIn: Int, numClasses: Int) {
        self.featIn = featIn
        self.numClasses = numClasses
    }
}

// MARK: - Model Variant Configurations

/// Configuration for ParakeetTDT (Token-and-Duration Transducer).
public struct ParakeetTDTArgs: Codable, Sendable {
    public var conformer: ConformerArgs
    public var predict: PredictNetworkArgs
    public var joint: JointNetworkArgs
    public var labels: [String]
    public var durations: [Int]
    public var preprocess: PreprocessArgs

    public init(conformer: ConformerArgs, predict: PredictNetworkArgs, joint: JointNetworkArgs, labels: [String], durations: [Int], preprocess: PreprocessArgs = PreprocessArgs()) {
        self.conformer = conformer
        self.predict = predict
        self.joint = joint
        self.labels = labels
        self.durations = durations
        self.preprocess = preprocess
    }
}

/// Configuration for ParakeetRNNT (standard RNN-Transducer).
public struct ParakeetRNNTArgs: Codable, Sendable {
    public var conformer: ConformerArgs
    public var predict: PredictNetworkArgs
    public var joint: JointNetworkArgs
    public var labels: [String]
    public var preprocess: PreprocessArgs

    public init(conformer: ConformerArgs, predict: PredictNetworkArgs, joint: JointNetworkArgs, labels: [String], preprocess: PreprocessArgs = PreprocessArgs()) {
        self.conformer = conformer
        self.predict = predict
        self.joint = joint
        self.labels = labels
        self.preprocess = preprocess
    }
}

/// Configuration for ParakeetCTC (CTC greedy decoder).
public struct ParakeetCTCArgs: Codable, Sendable {
    public var conformer: ConformerArgs
    public var decoder: ConvASRDecoderArgs
    public var labels: [String]
    public var preprocess: PreprocessArgs

    public init(conformer: ConformerArgs, decoder: ConvASRDecoderArgs, labels: [String], preprocess: PreprocessArgs = PreprocessArgs()) {
        self.conformer = conformer
        self.decoder = decoder
        self.labels = labels
        self.preprocess = preprocess
    }
}
