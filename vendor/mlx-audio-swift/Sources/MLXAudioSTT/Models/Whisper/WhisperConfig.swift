//
//  WhisperConfig.swift
//  MLXAudioSTT
//
//  Whisper model configuration matching mlx-audio Python implementation.
//

import Foundation
import MLXLMCommon

/// Model dimensions for Whisper architecture.
public struct ModelDimensions: Codable, Equatable {
    public var nMels: Int
    public var nAudioCtx: Int
    public var nAudioState: Int
    public var nAudioHead: Int
    public var nAudioLayer: Int
    public var nVocab: Int
    public var nTextCtx: Int
    public var nTextState: Int
    public var nTextHead: Int
    public var nTextLayer: Int

    enum CodingKeys: String, CodingKey {
        case nMels = "n_mels"
        case nAudioCtx = "n_audio_ctx"
        case nAudioState = "n_audio_state"
        case nAudioHead = "n_audio_head"
        case nAudioLayer = "n_audio_layer"
        case nVocab = "n_vocab"
        case nTextCtx = "n_text_ctx"
        case nTextState = "n_text_state"
        case nTextHead = "n_text_head"
        case nTextLayer = "n_text_layer"

        // HuggingFace format aliases
        case numMelBins = "num_mel_bins"
        case maxSourcePositions = "max_source_positions"
        case dModel = "d_model"
        case encoderAttentionHeads = "encoder_attention_heads"
        case encoderLayers = "encoder_layers"
        case vocabSize = "vocab_size"
        case maxTargetPositions = "max_target_positions"
        case decoderAttentionHeads = "decoder_attention_heads"
        case decoderLayers = "decoder_layers"
    }

    public init(
        nMels: Int = 80,
        nAudioCtx: Int = 1500,
        nAudioState: Int = 384,
        nAudioHead: Int = 6,
        nAudioLayer: Int = 4,
        nVocab: Int = 51864,
        nTextCtx: Int = 448,
        nTextState: Int = 384,
        nTextHead: Int = 6,
        nTextLayer: Int = 4
    ) {
        self.nMels = nMels
        self.nAudioCtx = nAudioCtx
        self.nAudioState = nAudioState
        self.nAudioHead = nAudioHead
        self.nAudioLayer = nAudioLayer
        self.nVocab = nVocab
        self.nTextCtx = nTextCtx
        self.nTextState = nTextState
        self.nTextHead = nTextHead
        self.nTextLayer = nTextLayer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try MLX format first, then HuggingFace format
        nMels = try container.decodeIfPresent(Int.self, forKey: .nMels)
            ?? container.decodeIfPresent(Int.self, forKey: .numMelBins) ?? 80

        nAudioCtx = try container.decodeIfPresent(Int.self, forKey: .nAudioCtx)
            ?? container.decodeIfPresent(Int.self, forKey: .maxSourcePositions) ?? 1500

        nAudioState = try container.decodeIfPresent(Int.self, forKey: .nAudioState)
            ?? container.decodeIfPresent(Int.self, forKey: .dModel) ?? 384

        nAudioHead = try container.decodeIfPresent(Int.self, forKey: .nAudioHead)
            ?? container.decodeIfPresent(Int.self, forKey: .encoderAttentionHeads) ?? 6

        nAudioLayer = try container.decodeIfPresent(Int.self, forKey: .nAudioLayer)
            ?? container.decodeIfPresent(Int.self, forKey: .encoderLayers) ?? 4

        nVocab = try container.decodeIfPresent(Int.self, forKey: .nVocab)
            ?? container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 51864

        nTextCtx = try container.decodeIfPresent(Int.self, forKey: .nTextCtx)
            ?? container.decodeIfPresent(Int.self, forKey: .maxTargetPositions) ?? 448

        nTextState = try container.decodeIfPresent(Int.self, forKey: .nTextState)
            ?? container.decodeIfPresent(Int.self, forKey: .dModel) ?? 384

        nTextHead = try container.decodeIfPresent(Int.self, forKey: .nTextHead)
            ?? container.decodeIfPresent(Int.self, forKey: .decoderAttentionHeads) ?? 6

        nTextLayer = try container.decodeIfPresent(Int.self, forKey: .nTextLayer)
            ?? container.decodeIfPresent(Int.self, forKey: .decoderLayers) ?? 4
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nMels, forKey: .nMels)
        try container.encode(nAudioCtx, forKey: .nAudioCtx)
        try container.encode(nAudioState, forKey: .nAudioState)
        try container.encode(nAudioHead, forKey: .nAudioHead)
        try container.encode(nAudioLayer, forKey: .nAudioLayer)
        try container.encode(nVocab, forKey: .nVocab)
        try container.encode(nTextCtx, forKey: .nTextCtx)
        try container.encode(nTextState, forKey: .nTextState)
        try container.encode(nTextHead, forKey: .nTextHead)
        try container.encode(nTextLayer, forKey: .nTextLayer)
    }
}

/// Configuration for the Whisper model.
public struct WhisperModelConfig: Codable {
    public var modelType: String
    public var dimensions: ModelDimensions
    public var perLayerQuantization: BaseConfiguration.PerLayerQuantization?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
    }

    public init(
        modelType: String = "whisper",
        dimensions: ModelDimensions = ModelDimensions(),
        perLayerQuantization: BaseConfiguration.PerLayerQuantization? = nil
    ) {
        self.modelType = modelType
        self.dimensions = dimensions
        self.perLayerQuantization = perLayerQuantization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "whisper"

        // Decode dimensions from the same container
        dimensions = try ModelDimensions(from: decoder)

        // Decode quantization from BaseConfiguration
        let baseConfig = try? BaseConfiguration(from: decoder)
        perLayerQuantization = baseConfig?.perLayerQuantization
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try dimensions.encode(to: encoder)
    }
}
