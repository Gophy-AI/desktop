//
//  VoxtralRealtimeConfig.swift
//  MLXAudioSTT
//
// Configuration for Voxtral Mini 4B Realtime model (Mistral-native format)

import Foundation

/// Audio encoding arguments for the Voxtral Realtime encoder.
public struct VoxtralRealtimeAudioEncodingArgs: Codable {
    public var numMelBins: Int

    enum CodingKeys: String, CodingKey {
        case numMelBins = "num_mel_bins"
    }

    public init(numMelBins: Int = 128) {
        self.numMelBins = numMelBins
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numMelBins = try container.decodeIfPresent(Int.self, forKey: .numMelBins) ?? 128
    }
}

/// Encoder arguments for the Voxtral Realtime causal whisper encoder.
public struct VoxtralRealtimeEncoderArgs: Codable {
    public var dim: Int
    public var nLayers: Int
    public var nHeads: Int
    public var headDim: Int
    public var hiddenDim: Int
    public var ropeTheta: Float
    public var slidingWindow: Int
    public var audioEncodingArgs: VoxtralRealtimeAudioEncodingArgs

    enum CodingKeys: String, CodingKey {
        case dim
        case nLayers = "n_layers"
        case nHeads = "n_heads"
        case headDim = "head_dim"
        case hiddenDim = "hidden_dim"
        case ropeTheta = "rope_theta"
        case slidingWindow = "sliding_window"
        case audioEncodingArgs = "audio_encoding_args"
    }

    public init(
        dim: Int = 1280,
        nLayers: Int = 32,
        nHeads: Int = 32,
        headDim: Int = 64,
        hiddenDim: Int = 5120,
        ropeTheta: Float = 1000000.0,
        slidingWindow: Int = 750,
        audioEncodingArgs: VoxtralRealtimeAudioEncodingArgs = VoxtralRealtimeAudioEncodingArgs()
    ) {
        self.dim = dim
        self.nLayers = nLayers
        self.nHeads = nHeads
        self.headDim = headDim
        self.hiddenDim = hiddenDim
        self.ropeTheta = ropeTheta
        self.slidingWindow = slidingWindow
        self.audioEncodingArgs = audioEncodingArgs
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dim = try container.decodeIfPresent(Int.self, forKey: .dim) ?? 1280
        nLayers = try container.decodeIfPresent(Int.self, forKey: .nLayers) ?? 32
        nHeads = try container.decodeIfPresent(Int.self, forKey: .nHeads) ?? 32
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 64
        hiddenDim = try container.decodeIfPresent(Int.self, forKey: .hiddenDim) ?? 5120
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 1000000.0
        slidingWindow = try container.decodeIfPresent(Int.self, forKey: .slidingWindow) ?? 750
        audioEncodingArgs = try container.decodeIfPresent(
            VoxtralRealtimeAudioEncodingArgs.self, forKey: .audioEncodingArgs
        ) ?? VoxtralRealtimeAudioEncodingArgs()
    }
}

/// Downsample arguments.
public struct VoxtralRealtimeDownsampleArgs: Codable {
    public var downsampleFactor: Int

    enum CodingKeys: String, CodingKey {
        case downsampleFactor = "downsample_factor"
    }

    public init(downsampleFactor: Int = 4) {
        self.downsampleFactor = downsampleFactor
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downsampleFactor = try container.decodeIfPresent(Int.self, forKey: .downsampleFactor) ?? 4
    }
}

/// Whisper model arguments (encoder + downsample).
public struct VoxtralRealtimeWhisperModelArgs: Codable {
    public var encoderArgs: VoxtralRealtimeEncoderArgs
    public var downsampleArgs: VoxtralRealtimeDownsampleArgs

    enum CodingKeys: String, CodingKey {
        case encoderArgs = "encoder_args"
        case downsampleArgs = "downsample_args"
    }

    public init(
        encoderArgs: VoxtralRealtimeEncoderArgs = VoxtralRealtimeEncoderArgs(),
        downsampleArgs: VoxtralRealtimeDownsampleArgs = VoxtralRealtimeDownsampleArgs()
    ) {
        self.encoderArgs = encoderArgs
        self.downsampleArgs = downsampleArgs
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        encoderArgs = try container.decodeIfPresent(
            VoxtralRealtimeEncoderArgs.self, forKey: .encoderArgs
        ) ?? VoxtralRealtimeEncoderArgs()
        downsampleArgs = try container.decodeIfPresent(
            VoxtralRealtimeDownsampleArgs.self, forKey: .downsampleArgs
        ) ?? VoxtralRealtimeDownsampleArgs()
    }
}

/// Multimodal arguments.
public struct VoxtralRealtimeMultimodalArgs: Codable {
    public var whisperModelArgs: VoxtralRealtimeWhisperModelArgs

    enum CodingKeys: String, CodingKey {
        case whisperModelArgs = "whisper_model_args"
    }

    public init(whisperModelArgs: VoxtralRealtimeWhisperModelArgs = VoxtralRealtimeWhisperModelArgs()) {
        self.whisperModelArgs = whisperModelArgs
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        whisperModelArgs = try container.decodeIfPresent(
            VoxtralRealtimeWhisperModelArgs.self, forKey: .whisperModelArgs
        ) ?? VoxtralRealtimeWhisperModelArgs()
    }
}

/// Quantization configuration.
public struct VoxtralRealtimeQuantizationConfig: Codable {
    public var groupSize: Int
    public var bits: Int

    enum CodingKeys: String, CodingKey {
        case groupSize = "group_size"
        case bits
    }

    public init(groupSize: Int = 64, bits: Int = 6) {
        self.groupSize = groupSize
        self.bits = bits
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupSize = try container.decodeIfPresent(Int.self, forKey: .groupSize) ?? 64
        bits = try container.decodeIfPresent(Int.self, forKey: .bits) ?? 6
    }
}

/// Top-level configuration for Voxtral Realtime (Mistral-native format).
public struct VoxtralRealtimeConfig: Codable {
    public var dim: Int
    public var nLayers: Int
    public var nHeads: Int
    public var nKvHeads: Int
    public var headDim: Int
    public var hiddenDim: Int
    public var vocabSize: Int
    public var ropeTheta: Float
    public var multimodal: VoxtralRealtimeMultimodalArgs
    public var adaRmsNormTCond: Bool
    public var adaRmsNormTCondDim: Int
    public var quantization: VoxtralRealtimeQuantizationConfig?

    enum CodingKeys: String, CodingKey {
        case dim
        case nLayers = "n_layers"
        case nHeads = "n_heads"
        case nKvHeads = "n_kv_heads"
        case headDim = "head_dim"
        case hiddenDim = "hidden_dim"
        case vocabSize = "vocab_size"
        case ropeTheta = "rope_theta"
        case multimodal
        case adaRmsNormTCond = "ada_rms_norm_t_cond"
        case adaRmsNormTCondDim = "ada_rms_norm_t_cond_dim"
        case quantization
    }

    public init(
        dim: Int = 3072,
        nLayers: Int = 26,
        nHeads: Int = 32,
        nKvHeads: Int = 8,
        headDim: Int = 128,
        hiddenDim: Int = 9216,
        vocabSize: Int = 131072,
        ropeTheta: Float = 1000000.0,
        multimodal: VoxtralRealtimeMultimodalArgs = VoxtralRealtimeMultimodalArgs(),
        adaRmsNormTCond: Bool = true,
        adaRmsNormTCondDim: Int = 32,
        quantization: VoxtralRealtimeQuantizationConfig? = nil
    ) {
        self.dim = dim
        self.nLayers = nLayers
        self.nHeads = nHeads
        self.nKvHeads = nKvHeads
        self.headDim = headDim
        self.hiddenDim = hiddenDim
        self.vocabSize = vocabSize
        self.ropeTheta = ropeTheta
        self.multimodal = multimodal
        self.adaRmsNormTCond = adaRmsNormTCond
        self.adaRmsNormTCondDim = adaRmsNormTCondDim
        self.quantization = quantization
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dim = try container.decodeIfPresent(Int.self, forKey: .dim) ?? 3072
        nLayers = try container.decodeIfPresent(Int.self, forKey: .nLayers) ?? 26
        nHeads = try container.decodeIfPresent(Int.self, forKey: .nHeads) ?? 32
        nKvHeads = try container.decodeIfPresent(Int.self, forKey: .nKvHeads) ?? 8
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 128
        hiddenDim = try container.decodeIfPresent(Int.self, forKey: .hiddenDim) ?? 9216
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 131072
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 1000000.0
        multimodal = try container.decodeIfPresent(
            VoxtralRealtimeMultimodalArgs.self, forKey: .multimodal
        ) ?? VoxtralRealtimeMultimodalArgs()
        adaRmsNormTCond = try container.decodeIfPresent(Bool.self, forKey: .adaRmsNormTCond) ?? true
        adaRmsNormTCondDim = try container.decodeIfPresent(Int.self, forKey: .adaRmsNormTCondDim) ?? 32
        quantization = try container.decodeIfPresent(VoxtralRealtimeQuantizationConfig.self, forKey: .quantization)
    }
}
