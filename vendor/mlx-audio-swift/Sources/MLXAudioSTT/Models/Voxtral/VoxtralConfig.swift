//
//  VoxtralConfig.swift
//  MLXAudioSTT
//
// Voxtral model configuration structures matching mlx_audio Python config

import Foundation
import MLXLMCommon

/// Configuration for the Voxtral audio encoder.
public struct VoxtralAudioConfig: Codable {
    public var hiddenSize: Int
    public var numHiddenLayers: Int
    public var intermediateSize: Int
    public var numAttentionHeads: Int
    public var numKeyValueHeads: Int
    public var rmsNormEps: Float
    public var headDim: Int
    public var ropeTheta: Float
    public var vocabSize: Int
    public var numMelBins: Int
    public var encoderLayers: Int
    public var encoderAttentionHeads: Int
    public var encoderFfnDim: Int
    public var encoderLayerdrop: Float
    public var dModel: Int
    public var dropout: Float
    public var attentionDropout: Float
    public var activationFunction: String
    public var activationDropout: Float
    public var scaleEmbedding: Bool
    public var initializerRange: Float
    public var maxSourcePositions: Int

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case rmsNormEps = "rms_norm_eps"
        case headDim = "head_dim"
        case ropeTheta = "rope_theta"
        case vocabSize = "vocab_size"
        case numMelBins = "num_mel_bins"
        case encoderLayers = "encoder_layers"
        case encoderAttentionHeads = "encoder_attention_heads"
        case encoderFfnDim = "encoder_ffn_dim"
        case encoderLayerdrop = "encoder_layerdrop"
        case dModel = "d_model"
        case dropout
        case attentionDropout = "attention_dropout"
        case activationFunction = "activation_function"
        case activationDropout = "activation_dropout"
        case scaleEmbedding = "scale_embedding"
        case initializerRange = "initializer_range"
        case maxSourcePositions = "max_source_positions"
    }

    public init(
        hiddenSize: Int = 1280,
        numHiddenLayers: Int = 32,
        intermediateSize: Int = 5120,
        numAttentionHeads: Int = 20,
        numKeyValueHeads: Int = 20,
        rmsNormEps: Float = 1e-5,
        headDim: Int = 64,
        ropeTheta: Float = 1000000.0,
        vocabSize: Int = 51866,
        numMelBins: Int = 128,
        encoderLayers: Int = 32,
        encoderAttentionHeads: Int = 20,
        encoderFfnDim: Int = 5120,
        encoderLayerdrop: Float = 0.0,
        dModel: Int = 1280,
        dropout: Float = 0.0,
        attentionDropout: Float = 0.0,
        activationFunction: String = "gelu",
        activationDropout: Float = 0.0,
        scaleEmbedding: Bool = false,
        initializerRange: Float = 0.02,
        maxSourcePositions: Int = 1500
    ) {
        self.hiddenSize = hiddenSize
        self.numHiddenLayers = numHiddenLayers
        self.intermediateSize = intermediateSize
        self.numAttentionHeads = numAttentionHeads
        self.numKeyValueHeads = numKeyValueHeads
        self.rmsNormEps = rmsNormEps
        self.headDim = headDim
        self.ropeTheta = ropeTheta
        self.vocabSize = vocabSize
        self.numMelBins = numMelBins
        self.encoderLayers = encoderLayers
        self.encoderAttentionHeads = encoderAttentionHeads
        self.encoderFfnDim = encoderFfnDim
        self.encoderLayerdrop = encoderLayerdrop
        self.dModel = dModel
        self.dropout = dropout
        self.attentionDropout = attentionDropout
        self.activationFunction = activationFunction
        self.activationDropout = activationDropout
        self.scaleEmbedding = scaleEmbedding
        self.initializerRange = initializerRange
        self.maxSourcePositions = maxSourcePositions
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 1280
        numHiddenLayers = try container.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 32
        intermediateSize = try container.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 5120
        numAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 20
        numKeyValueHeads = try container.decodeIfPresent(Int.self, forKey: .numKeyValueHeads) ?? 20
        rmsNormEps = try container.decodeIfPresent(Float.self, forKey: .rmsNormEps) ?? 1e-5
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 64
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 1000000.0
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 51866
        numMelBins = try container.decodeIfPresent(Int.self, forKey: .numMelBins) ?? 128
        encoderLayers = try container.decodeIfPresent(Int.self, forKey: .encoderLayers) ?? 32
        encoderAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .encoderAttentionHeads) ?? 20
        encoderFfnDim = try container.decodeIfPresent(Int.self, forKey: .encoderFfnDim) ?? 5120
        encoderLayerdrop = try container.decodeIfPresent(Float.self, forKey: .encoderLayerdrop) ?? 0.0
        dModel = try container.decodeIfPresent(Int.self, forKey: .dModel) ?? 1280
        dropout = try container.decodeIfPresent(Float.self, forKey: .dropout) ?? 0.0
        attentionDropout = try container.decodeIfPresent(Float.self, forKey: .attentionDropout) ?? 0.0
        activationFunction = try container.decodeIfPresent(String.self, forKey: .activationFunction) ?? "gelu"
        activationDropout = try container.decodeIfPresent(Float.self, forKey: .activationDropout) ?? 0.0
        scaleEmbedding = try container.decodeIfPresent(Bool.self, forKey: .scaleEmbedding) ?? false
        initializerRange = try container.decodeIfPresent(Float.self, forKey: .initializerRange) ?? 0.02
        maxSourcePositions = try container.decodeIfPresent(Int.self, forKey: .maxSourcePositions) ?? 1500
    }
}

/// Configuration for the Voxtral text decoder (Llama-compatible).
public struct VoxtralTextConfig: Codable {
    public var modelType: String
    public var vocabSize: Int
    public var maxPositionEmbeddings: Int
    public var hiddenSize: Int
    public var intermediateSize: Int
    public var numHiddenLayers: Int
    public var numAttentionHeads: Int
    public var numKeyValueHeads: Int
    public var hiddenAct: String
    public var initializerRange: Float
    public var rmsNormEps: Float
    public var useCache: Bool
    public var ropeScaling: [String: AnyCodable]?
    public var attentionBias: Bool
    public var attentionDropout: Float
    public var mlpBias: Bool
    public var headDim: Int
    public var tieWordEmbeddings: Bool
    public var bosTokenId: Int
    public var eosTokenId: Int
    public var slidingWindow: Int?
    public var ropeTraditional: Bool
    public var ropeTheta: Float
    public var layerTypes: [String]

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case vocabSize = "vocab_size"
        case maxPositionEmbeddings = "max_position_embeddings"
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case hiddenAct = "hidden_act"
        case initializerRange = "initializer_range"
        case rmsNormEps = "rms_norm_eps"
        case useCache = "use_cache"
        case ropeScaling = "rope_scaling"
        case attentionBias = "attention_bias"
        case attentionDropout = "attention_dropout"
        case mlpBias = "mlp_bias"
        case headDim = "head_dim"
        case tieWordEmbeddings = "tie_word_embeddings"
        case bosTokenId = "bos_token_id"
        case eosTokenId = "eos_token_id"
        case slidingWindow = "sliding_window"
        case ropeTraditional = "rope_traditional"
        case ropeTheta = "rope_theta"
        case layerTypes = "layer_types"
    }

    public init(
        modelType: String = "llama",
        vocabSize: Int = 131072,
        maxPositionEmbeddings: Int = 131072,
        hiddenSize: Int = 3072,
        intermediateSize: Int = 8192,
        numHiddenLayers: Int = 30,
        numAttentionHeads: Int = 32,
        numKeyValueHeads: Int = 8,
        hiddenAct: String = "silu",
        initializerRange: Float = 0.02,
        rmsNormEps: Float = 1e-5,
        useCache: Bool = true,
        ropeScaling: [String: AnyCodable]? = nil,
        attentionBias: Bool = false,
        attentionDropout: Float = 0.0,
        mlpBias: Bool = false,
        headDim: Int = 128,
        tieWordEmbeddings: Bool = false,
        bosTokenId: Int = 1,
        eosTokenId: Int = 2,
        slidingWindow: Int? = nil,
        ropeTraditional: Bool = false,
        ropeTheta: Float = 100000000.0,
        layerTypes: [String]? = nil
    ) {
        self.modelType = modelType
        self.vocabSize = vocabSize
        self.maxPositionEmbeddings = maxPositionEmbeddings
        self.hiddenSize = hiddenSize
        self.intermediateSize = intermediateSize
        self.numHiddenLayers = numHiddenLayers
        self.numAttentionHeads = numAttentionHeads
        self.numKeyValueHeads = numKeyValueHeads
        self.hiddenAct = hiddenAct
        self.initializerRange = initializerRange
        self.rmsNormEps = rmsNormEps
        self.useCache = useCache
        self.ropeScaling = ropeScaling
        self.attentionBias = attentionBias
        self.attentionDropout = attentionDropout
        self.mlpBias = mlpBias
        self.headDim = headDim
        self.tieWordEmbeddings = tieWordEmbeddings
        self.bosTokenId = bosTokenId
        self.eosTokenId = eosTokenId
        self.slidingWindow = slidingWindow
        self.ropeTraditional = ropeTraditional
        self.ropeTheta = ropeTheta
        self.layerTypes = layerTypes ?? Array(repeating: "full_attention", count: numHiddenLayers)
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "llama"
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 131072
        maxPositionEmbeddings = try container.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings) ?? 131072
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 3072
        intermediateSize = try container.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 8192
        numHiddenLayers = try container.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 30
        numAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 32
        numKeyValueHeads = try container.decodeIfPresent(Int.self, forKey: .numKeyValueHeads) ?? 8
        hiddenAct = try container.decodeIfPresent(String.self, forKey: .hiddenAct) ?? "silu"
        initializerRange = try container.decodeIfPresent(Float.self, forKey: .initializerRange) ?? 0.02
        rmsNormEps = try container.decodeIfPresent(Float.self, forKey: .rmsNormEps) ?? 1e-5
        useCache = try container.decodeIfPresent(Bool.self, forKey: .useCache) ?? true
        ropeScaling = try container.decodeIfPresent([String: AnyCodable].self, forKey: .ropeScaling)
        attentionBias = try container.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        attentionDropout = try container.decodeIfPresent(Float.self, forKey: .attentionDropout) ?? 0.0
        mlpBias = try container.decodeIfPresent(Bool.self, forKey: .mlpBias) ?? false
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 128
        tieWordEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? false
        bosTokenId = try container.decodeIfPresent(Int.self, forKey: .bosTokenId) ?? 1
        eosTokenId = try container.decodeIfPresent(Int.self, forKey: .eosTokenId) ?? 2
        slidingWindow = try container.decodeIfPresent(Int.self, forKey: .slidingWindow)
        ropeTraditional = try container.decodeIfPresent(Bool.self, forKey: .ropeTraditional) ?? false
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 100000000.0
        let layers = try container.decodeIfPresent([String].self, forKey: .layerTypes)
        layerTypes = layers ?? Array(repeating: "full_attention", count: numHiddenLayers)
    }
}

/// Configuration for the complete Voxtral model.
public struct VoxtralModelConfig: Codable {
    public var audioConfig: VoxtralAudioConfig
    public var textConfig: VoxtralTextConfig
    public var modelRepo: String?
    public var modelType: String
    public var audioTokenId: Int
    public var projectorHiddenAct: String
    public var vocabSize: Int
    public var hiddenSize: Int

    enum CodingKeys: String, CodingKey {
        case audioConfig = "audio_config"
        case textConfig = "text_config"
        case modelRepo = "model_repo"
        case modelType = "model_type"
        case audioTokenId = "audio_token_id"
        case projectorHiddenAct = "projector_hidden_act"
        case vocabSize = "vocab_size"
        case hiddenSize = "hidden_size"
    }

    public init(
        audioConfig: VoxtralAudioConfig = VoxtralAudioConfig(),
        textConfig: VoxtralTextConfig = VoxtralTextConfig(),
        modelRepo: String? = nil,
        modelType: String = "voxtral",
        audioTokenId: Int = 24,
        projectorHiddenAct: String = "gelu",
        vocabSize: Int = 131072,
        hiddenSize: Int = 3072
    ) {
        self.audioConfig = audioConfig
        self.textConfig = textConfig
        self.modelRepo = modelRepo
        self.modelType = modelType
        self.audioTokenId = audioTokenId
        self.projectorHiddenAct = projectorHiddenAct
        self.vocabSize = textConfig.vocabSize
        self.hiddenSize = textConfig.hiddenSize
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioConfig = try container.decodeIfPresent(VoxtralAudioConfig.self, forKey: .audioConfig) ?? VoxtralAudioConfig()
        textConfig = try container.decodeIfPresent(VoxtralTextConfig.self, forKey: .textConfig) ?? VoxtralTextConfig()
        modelRepo = try container.decodeIfPresent(String.self, forKey: .modelRepo)
        modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "voxtral"
        audioTokenId = try container.decodeIfPresent(Int.self, forKey: .audioTokenId) ?? 24
        projectorHiddenAct = try container.decodeIfPresent(String.self, forKey: .projectorHiddenAct) ?? "gelu"
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? textConfig.vocabSize
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? textConfig.hiddenSize
    }
}
