//
//  Qwen3ASRConfig.swift
//  MLXAudioSTT
//
// Qwen3 ASR configuration structs.
//

import Foundation
import MLXLMCommon

/// Configuration for the Qwen3 ASR audio encoder.
public struct AudioEncoderConfig: Codable {
    public var numMelBins: Int
    public var encoderLayers: Int
    public var encoderAttentionHeads: Int
    public var encoderFfnDim: Int
    public var dModel: Int
    public var dropout: Float
    public var attentionDropout: Float
    public var activationFunction: String
    public var activationDropout: Float
    public var scaleEmbedding: Bool
    public var initializerRange: Float
    public var maxSourcePositions: Int
    public var nWindow: Int
    public var outputDim: Int
    public var nWindowInfer: Int
    public var convChunksize: Int
    public var downsampleHiddenSize: Int

    enum CodingKeys: String, CodingKey {
        case numMelBins = "num_mel_bins"
        case encoderLayers = "encoder_layers"
        case encoderAttentionHeads = "encoder_attention_heads"
        case encoderFfnDim = "encoder_ffn_dim"
        case dModel = "d_model"
        case dropout
        case attentionDropout = "attention_dropout"
        case activationFunction = "activation_function"
        case activationDropout = "activation_dropout"
        case scaleEmbedding = "scale_embedding"
        case initializerRange = "initializer_range"
        case maxSourcePositions = "max_source_positions"
        case nWindow = "n_window"
        case outputDim = "output_dim"
        case nWindowInfer = "n_window_infer"
        case convChunksize = "conv_chunksize"
        case downsampleHiddenSize = "downsample_hidden_size"
    }

    public init(
        numMelBins: Int = 128,
        encoderLayers: Int = 24,
        encoderAttentionHeads: Int = 16,
        encoderFfnDim: Int = 4096,
        dModel: Int = 1024,
        dropout: Float = 0.0,
        attentionDropout: Float = 0.0,
        activationFunction: String = "gelu",
        activationDropout: Float = 0.0,
        scaleEmbedding: Bool = false,
        initializerRange: Float = 0.02,
        maxSourcePositions: Int = 1500,
        nWindow: Int = 50,
        outputDim: Int = 2048,
        nWindowInfer: Int = 800,
        convChunksize: Int = 500,
        downsampleHiddenSize: Int = 480
    ) {
        self.numMelBins = numMelBins
        self.encoderLayers = encoderLayers
        self.encoderAttentionHeads = encoderAttentionHeads
        self.encoderFfnDim = encoderFfnDim
        self.dModel = dModel
        self.dropout = dropout
        self.attentionDropout = attentionDropout
        self.activationFunction = activationFunction
        self.activationDropout = activationDropout
        self.scaleEmbedding = scaleEmbedding
        self.initializerRange = initializerRange
        self.maxSourcePositions = maxSourcePositions
        self.nWindow = nWindow
        self.outputDim = outputDim
        self.nWindowInfer = nWindowInfer
        self.convChunksize = convChunksize
        self.downsampleHiddenSize = downsampleHiddenSize
    }
}

/// Configuration for the Qwen3 text decoder.
public struct TextConfig: Codable {
    public var modelType: String
    public var vocabSize: Int
    public var hiddenSize: Int
    public var intermediateSize: Int
    public var numHiddenLayers: Int
    public var numAttentionHeads: Int
    public var numKeyValueHeads: Int
    public var headDim: Int
    public var hiddenAct: String
    public var maxPositionEmbeddings: Int
    public var initializerRange: Float
    public var rmsNormEps: Float
    public var useCache: Bool
    public var tieWordEmbeddings: Bool
    public var ropeTheta: Float
    public var attentionBias: Bool
    public var attentionDropout: Float

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case vocabSize = "vocab_size"
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case hiddenAct = "hidden_act"
        case maxPositionEmbeddings = "max_position_embeddings"
        case initializerRange = "initializer_range"
        case rmsNormEps = "rms_norm_eps"
        case useCache = "use_cache"
        case tieWordEmbeddings = "tie_word_embeddings"
        case ropeTheta = "rope_theta"
        case attentionBias = "attention_bias"
        case attentionDropout = "attention_dropout"
    }

    public init(
        modelType: String = "qwen3",
        vocabSize: Int = 151936,
        hiddenSize: Int = 2048,
        intermediateSize: Int = 6144,
        numHiddenLayers: Int = 28,
        numAttentionHeads: Int = 16,
        numKeyValueHeads: Int = 8,
        headDim: Int = 128,
        hiddenAct: String = "silu",
        maxPositionEmbeddings: Int = 65536,
        initializerRange: Float = 0.02,
        rmsNormEps: Float = 1e-6,
        useCache: Bool = true,
        tieWordEmbeddings: Bool = true,
        ropeTheta: Float = 1000000.0,
        attentionBias: Bool = false,
        attentionDropout: Float = 0.0
    ) {
        self.modelType = modelType
        self.vocabSize = vocabSize
        self.hiddenSize = hiddenSize
        self.intermediateSize = intermediateSize
        self.numHiddenLayers = numHiddenLayers
        self.numAttentionHeads = numAttentionHeads
        self.numKeyValueHeads = numKeyValueHeads
        self.headDim = headDim
        self.hiddenAct = hiddenAct
        self.maxPositionEmbeddings = maxPositionEmbeddings
        self.initializerRange = initializerRange
        self.rmsNormEps = rmsNormEps
        self.useCache = useCache
        self.tieWordEmbeddings = tieWordEmbeddings
        self.ropeTheta = ropeTheta
        self.attentionBias = attentionBias
        self.attentionDropout = attentionDropout
    }
}

/// Configuration for the Qwen3 ASR model.
public struct Qwen3ASRModelConfig: Codable {
    public var modelType: String
    public var audioConfig: AudioEncoderConfig
    public var textConfig: TextConfig
    public var audioTokenId: Int
    public var audioStartTokenId: Int
    public var audioEndTokenId: Int
    public var supportLanguages: [String]

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case audioConfig = "audio_config"
        case textConfig = "text_config"
        case audioTokenId = "audio_token_id"
        case audioStartTokenId = "audio_start_token_id"
        case audioEndTokenId = "audio_end_token_id"
        case supportLanguages = "support_languages"
        case thinkerConfig = "thinker_config"
    }

    public init(
        modelType: String = "qwen3_asr",
        audioConfig: AudioEncoderConfig = AudioEncoderConfig(),
        textConfig: TextConfig = TextConfig(),
        audioTokenId: Int = 151676,
        audioStartTokenId: Int = 151669,
        audioEndTokenId: Int = 151670,
        supportLanguages: [String] = []
    ) {
        self.modelType = modelType
        self.audioConfig = audioConfig
        self.textConfig = textConfig
        self.audioTokenId = audioTokenId
        self.audioStartTokenId = audioStartTokenId
        self.audioEndTokenId = audioEndTokenId
        self.supportLanguages = supportLanguages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Check for thinker_config nesting (HuggingFace format)
        if let thinkerConfig = try? container.decode([String: CodableWrapper].self, forKey: .thinkerConfig) {
            // Extract from thinker_config
            if let audioConfigDict = thinkerConfig["audio_config"]?.value as? [String: Any],
               let audioConfigData = try? JSONSerialization.data(withJSONObject: audioConfigDict),
               let audioConfig = try? JSONDecoder().decode(AudioEncoderConfig.self, from: audioConfigData) {
                self.audioConfig = audioConfig
            } else {
                self.audioConfig = AudioEncoderConfig()
            }

            if let textConfigDict = thinkerConfig["text_config"]?.value as? [String: Any],
               let textConfigData = try? JSONSerialization.data(withJSONObject: textConfigDict),
               let textConfig = try? JSONDecoder().decode(TextConfig.self, from: textConfigData) {
                self.textConfig = textConfig
            } else {
                self.textConfig = TextConfig()
            }

            if let audioTokenId = thinkerConfig["audio_token_id"]?.value as? Int {
                self.audioTokenId = audioTokenId
            } else {
                self.audioTokenId = 151676
            }

            if let audioStartTokenId = thinkerConfig["audio_start_token_id"]?.value as? Int {
                self.audioStartTokenId = audioStartTokenId
            } else {
                self.audioStartTokenId = 151669
            }

            if let audioEndTokenId = thinkerConfig["audio_end_token_id"]?.value as? Int {
                self.audioEndTokenId = audioEndTokenId
            } else {
                self.audioEndTokenId = 151670
            }

            self.modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "qwen3_asr"
            self.supportLanguages = try container.decodeIfPresent([String].self, forKey: .supportLanguages) ?? []
        } else {
            // Standard format
            self.modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "qwen3_asr"
            self.audioConfig = try container.decodeIfPresent(AudioEncoderConfig.self, forKey: .audioConfig) ?? AudioEncoderConfig()
            self.textConfig = try container.decodeIfPresent(TextConfig.self, forKey: .textConfig) ?? TextConfig()
            self.audioTokenId = try container.decodeIfPresent(Int.self, forKey: .audioTokenId) ?? 151676
            self.audioStartTokenId = try container.decodeIfPresent(Int.self, forKey: .audioStartTokenId) ?? 151669
            self.audioEndTokenId = try container.decodeIfPresent(Int.self, forKey: .audioEndTokenId) ?? 151670
            self.supportLanguages = try container.decodeIfPresent([String].self, forKey: .supportLanguages) ?? []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(audioConfig, forKey: .audioConfig)
        try container.encode(textConfig, forKey: .textConfig)
        try container.encode(audioTokenId, forKey: .audioTokenId)
        try container.encode(audioStartTokenId, forKey: .audioStartTokenId)
        try container.encode(audioEndTokenId, forKey: .audioEndTokenId)
        try container.encode(supportLanguages, forKey: .supportLanguages)
    }
}

/// Configuration for the Qwen3 Forced Aligner model.
public struct ForcedAlignerConfig: Codable {
    public var modelType: String
    public var audioConfig: AudioEncoderConfig
    public var textConfig: TextConfig
    public var audioTokenId: Int
    public var audioStartTokenId: Int
    public var audioEndTokenId: Int
    public var supportLanguages: [String]
    public var timestampTokenId: Int
    public var classifyNum: Int

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case audioConfig = "audio_config"
        case textConfig = "text_config"
        case audioTokenId = "audio_token_id"
        case audioStartTokenId = "audio_start_token_id"
        case audioEndTokenId = "audio_end_token_id"
        case supportLanguages = "support_languages"
        case timestampTokenId = "timestamp_token_id"
        case classifyNum = "classify_num"
        case thinkerConfig = "thinker_config"
    }

    public init(
        modelType: String = "qwen3_forced_aligner",
        audioConfig: AudioEncoderConfig = AudioEncoderConfig(),
        textConfig: TextConfig = TextConfig(),
        audioTokenId: Int = 151676,
        audioStartTokenId: Int = 151669,
        audioEndTokenId: Int = 151670,
        supportLanguages: [String] = [],
        timestampTokenId: Int = 151671,
        classifyNum: Int = 5000
    ) {
        self.modelType = modelType
        self.audioConfig = audioConfig
        self.textConfig = textConfig
        self.audioTokenId = audioTokenId
        self.audioStartTokenId = audioStartTokenId
        self.audioEndTokenId = audioEndTokenId
        self.supportLanguages = supportLanguages
        self.timestampTokenId = timestampTokenId
        self.classifyNum = classifyNum
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Check for thinker_config nesting (HuggingFace format)
        if let thinkerConfig = try? container.decode([String: CodableWrapper].self, forKey: .thinkerConfig) {
            // Extract from thinker_config
            if let audioConfigDict = thinkerConfig["audio_config"]?.value as? [String: Any],
               let audioConfigData = try? JSONSerialization.data(withJSONObject: audioConfigDict),
               let audioConfig = try? JSONDecoder().decode(AudioEncoderConfig.self, from: audioConfigData) {
                self.audioConfig = audioConfig
            } else {
                self.audioConfig = AudioEncoderConfig()
            }

            if let textConfigDict = thinkerConfig["text_config"]?.value as? [String: Any],
               let textConfigData = try? JSONSerialization.data(withJSONObject: textConfigDict),
               let textConfig = try? JSONDecoder().decode(TextConfig.self, from: textConfigData) {
                self.textConfig = textConfig
            } else {
                self.textConfig = TextConfig()
            }

            self.audioTokenId = thinkerConfig["audio_token_id"]?.value as? Int ?? 151676
            self.audioStartTokenId = thinkerConfig["audio_start_token_id"]?.value as? Int ?? 151669
            self.audioEndTokenId = thinkerConfig["audio_end_token_id"]?.value as? Int ?? 151670
            self.timestampTokenId = thinkerConfig["timestamp_token_id"]?.value as? Int ?? 151671
            self.classifyNum = thinkerConfig["classify_num"]?.value as? Int ?? 5000

            self.modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "qwen3_forced_aligner"
            self.supportLanguages = try container.decodeIfPresent([String].self, forKey: .supportLanguages) ?? []
        } else {
            // Standard format
            self.modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "qwen3_forced_aligner"
            self.audioConfig = try container.decodeIfPresent(AudioEncoderConfig.self, forKey: .audioConfig) ?? AudioEncoderConfig()
            self.textConfig = try container.decodeIfPresent(TextConfig.self, forKey: .textConfig) ?? TextConfig()
            self.audioTokenId = try container.decodeIfPresent(Int.self, forKey: .audioTokenId) ?? 151676
            self.audioStartTokenId = try container.decodeIfPresent(Int.self, forKey: .audioStartTokenId) ?? 151669
            self.audioEndTokenId = try container.decodeIfPresent(Int.self, forKey: .audioEndTokenId) ?? 151670
            self.supportLanguages = try container.decodeIfPresent([String].self, forKey: .supportLanguages) ?? []
            self.timestampTokenId = try container.decodeIfPresent(Int.self, forKey: .timestampTokenId) ?? 151671
            self.classifyNum = try container.decodeIfPresent(Int.self, forKey: .classifyNum) ?? 5000
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(audioConfig, forKey: .audioConfig)
        try container.encode(textConfig, forKey: .textConfig)
        try container.encode(audioTokenId, forKey: .audioTokenId)
        try container.encode(audioStartTokenId, forKey: .audioStartTokenId)
        try container.encode(audioEndTokenId, forKey: .audioEndTokenId)
        try container.encode(supportLanguages, forKey: .supportLanguages)
        try container.encode(timestampTokenId, forKey: .timestampTokenId)
        try container.encode(classifyNum, forKey: .classifyNum)
    }
}

/// Helper for decoding arbitrary JSON values.
struct CodableWrapper: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([CodableWrapper].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: CodableWrapper].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { CodableWrapper($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { CodableWrapper($0) })
        default:
            try container.encodeNil()
        }
    }
}
