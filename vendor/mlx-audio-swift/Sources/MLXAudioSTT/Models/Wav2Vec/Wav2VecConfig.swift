//
//  Wav2VecConfig.swift
//  MLXAudioSTT
//
// Created by act agent on 08/02/2026.
//

import Foundation

public struct Wav2VecModelConfig: Codable {
    public var modelType: String
    public var convDim: [Int]
    public var convStride: [Int]
    public var convKernel: [Int]
    public var numConvPosEmbeddings: Int
    public var numConvPosEmbeddingGroups: Int
    public var hiddenSize: Int
    public var numHiddenLayers: Int
    public var numAttentionHeads: Int
    public var intermediateSize: Int
    public var hiddenAct: String
    public var featExtractNorm: String
    public var doStableLayerNorm: Bool
    public var layerNormEps: Float
    public var vocabSize: Int?
    public var hiddenDropout: Float
    public var activationDropout: Float
    public var attentionDropout: Float
    public var featProjDropout: Float
    public var finalDropout: Float

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case convDim = "conv_dim"
        case convStride = "conv_stride"
        case convKernel = "conv_kernel"
        case numConvPosEmbeddings = "num_conv_pos_embeddings"
        case numConvPosEmbeddingGroups = "num_conv_pos_embedding_groups"
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case intermediateSize = "intermediate_size"
        case hiddenAct = "hidden_act"
        case featExtractNorm = "feat_extract_norm"
        case doStableLayerNorm = "do_stable_layer_norm"
        case layerNormEps = "layer_norm_eps"
        case vocabSize = "vocab_size"
        case hiddenDropout = "hidden_dropout"
        case activationDropout = "activation_dropout"
        case attentionDropout = "attention_dropout"
        case featProjDropout = "feat_proj_dropout"
        case finalDropout = "final_dropout"
    }

    public init(
        modelType: String = "wav2vec2",
        convDim: [Int] = [512, 512, 512, 512, 512, 512, 512],
        convStride: [Int] = [5, 2, 2, 2, 2, 2, 2],
        convKernel: [Int] = [10, 3, 3, 3, 3, 2, 2],
        numConvPosEmbeddings: Int = 128,
        numConvPosEmbeddingGroups: Int = 16,
        hiddenSize: Int = 768,
        numHiddenLayers: Int = 12,
        numAttentionHeads: Int = 12,
        intermediateSize: Int = 3072,
        hiddenAct: String = "gelu",
        featExtractNorm: String = "group",
        doStableLayerNorm: Bool = false,
        layerNormEps: Float = 1e-5,
        vocabSize: Int? = nil,
        hiddenDropout: Float = 0.1,
        activationDropout: Float = 0.1,
        attentionDropout: Float = 0.1,
        featProjDropout: Float = 0.0,
        finalDropout: Float = 0.1
    ) {
        self.modelType = modelType
        self.convDim = convDim
        self.convStride = convStride
        self.convKernel = convKernel
        self.numConvPosEmbeddings = numConvPosEmbeddings
        self.numConvPosEmbeddingGroups = numConvPosEmbeddingGroups
        self.hiddenSize = hiddenSize
        self.numHiddenLayers = numHiddenLayers
        self.numAttentionHeads = numAttentionHeads
        self.intermediateSize = intermediateSize
        self.hiddenAct = hiddenAct
        self.featExtractNorm = featExtractNorm
        self.doStableLayerNorm = doStableLayerNorm
        self.layerNormEps = layerNormEps
        self.vocabSize = vocabSize
        self.hiddenDropout = hiddenDropout
        self.activationDropout = activationDropout
        self.attentionDropout = attentionDropout
        self.featProjDropout = featProjDropout
        self.finalDropout = finalDropout
    }

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "wav2vec2"
        convDim = try container.decodeIfPresent([Int].self, forKey: .convDim) ?? [512, 512, 512, 512, 512, 512, 512]
        convStride = try container.decodeIfPresent([Int].self, forKey: .convStride) ?? [5, 2, 2, 2, 2, 2, 2]
        convKernel = try container.decodeIfPresent([Int].self, forKey: .convKernel) ?? [10, 3, 3, 3, 3, 2, 2]
        numConvPosEmbeddings = try container.decodeIfPresent(Int.self, forKey: .numConvPosEmbeddings) ?? 128
        numConvPosEmbeddingGroups = try container.decodeIfPresent(Int.self, forKey: .numConvPosEmbeddingGroups) ?? 16
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 768
        numHiddenLayers = try container.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 12
        numAttentionHeads = try container.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 12
        intermediateSize = try container.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 3072
        hiddenAct = try container.decodeIfPresent(String.self, forKey: .hiddenAct) ?? "gelu"
        featExtractNorm = try container.decodeIfPresent(String.self, forKey: .featExtractNorm) ?? "group"
        doStableLayerNorm = try container.decodeIfPresent(Bool.self, forKey: .doStableLayerNorm) ?? false
        layerNormEps = try container.decodeIfPresent(Float.self, forKey: .layerNormEps) ?? 1e-5
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize)
        hiddenDropout = try container.decodeIfPresent(Float.self, forKey: .hiddenDropout) ?? 0.1
        activationDropout = try container.decodeIfPresent(Float.self, forKey: .activationDropout) ?? 0.1
        attentionDropout = try container.decodeIfPresent(Float.self, forKey: .attentionDropout) ?? 0.1
        featProjDropout = try container.decodeIfPresent(Float.self, forKey: .featProjDropout) ?? 0.0
        finalDropout = try container.decodeIfPresent(Float.self, forKey: .finalDropout) ?? 0.1
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(convDim, forKey: .convDim)
        try container.encode(convStride, forKey: .convStride)
        try container.encode(convKernel, forKey: .convKernel)
        try container.encode(numConvPosEmbeddings, forKey: .numConvPosEmbeddings)
        try container.encode(numConvPosEmbeddingGroups, forKey: .numConvPosEmbeddingGroups)
        try container.encode(hiddenSize, forKey: .hiddenSize)
        try container.encode(numHiddenLayers, forKey: .numHiddenLayers)
        try container.encode(numAttentionHeads, forKey: .numAttentionHeads)
        try container.encode(intermediateSize, forKey: .intermediateSize)
        try container.encode(hiddenAct, forKey: .hiddenAct)
        try container.encode(featExtractNorm, forKey: .featExtractNorm)
        try container.encode(doStableLayerNorm, forKey: .doStableLayerNorm)
        try container.encode(layerNormEps, forKey: .layerNormEps)
        try container.encodeIfPresent(vocabSize, forKey: .vocabSize)
        try container.encode(hiddenDropout, forKey: .hiddenDropout)
        try container.encode(activationDropout, forKey: .activationDropout)
        try container.encode(attentionDropout, forKey: .attentionDropout)
        try container.encode(featProjDropout, forKey: .featProjDropout)
        try container.encode(finalDropout, forKey: .finalDropout)
    }
}
