//
//  Wav2VecConfigTests.swift
//  MLXAudioSTTTests
//
// Created by act agent on 08/02/2026.
//

import XCTest
@testable import MLXAudioSTT

final class Wav2VecConfigTests: XCTestCase {

    func testConfigCodableRoundTrip() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [512, 512, 512, 512, 512, 512, 512],
            convStride: [5, 2, 2, 2, 2, 2, 2],
            convKernel: [10, 3, 3, 3, 3, 2, 2],
            numConvPosEmbeddings: 128,
            numConvPosEmbeddingGroups: 16,
            hiddenSize: 1024,
            numHiddenLayers: 24,
            numAttentionHeads: 16,
            intermediateSize: 4096,
            hiddenAct: "gelu",
            featExtractNorm: "group",
            doStableLayerNorm: false,
            layerNormEps: 1e-5,
            vocabSize: nil
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(config)

        // Decode from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Wav2VecModelConfig.self, from: data)

        // Verify all values match
        XCTAssertEqual(decoded.modelType, config.modelType)
        XCTAssertEqual(decoded.convDim, config.convDim)
        XCTAssertEqual(decoded.convStride, config.convStride)
        XCTAssertEqual(decoded.convKernel, config.convKernel)
        XCTAssertEqual(decoded.numConvPosEmbeddings, config.numConvPosEmbeddings)
        XCTAssertEqual(decoded.numConvPosEmbeddingGroups, config.numConvPosEmbeddingGroups)
        XCTAssertEqual(decoded.hiddenSize, config.hiddenSize)
        XCTAssertEqual(decoded.numHiddenLayers, config.numHiddenLayers)
        XCTAssertEqual(decoded.numAttentionHeads, config.numAttentionHeads)
        XCTAssertEqual(decoded.intermediateSize, config.intermediateSize)
        XCTAssertEqual(decoded.hiddenAct, config.hiddenAct)
        XCTAssertEqual(decoded.featExtractNorm, config.featExtractNorm)
        XCTAssertEqual(decoded.doStableLayerNorm, config.doStableLayerNorm)
        XCTAssertEqual(decoded.layerNormEps, config.layerNormEps, accuracy: 1e-10)
    }

    func testStableLayerNormFlag() throws {
        // Test false variant
        let configStandard = Wav2VecModelConfig(
            modelType: "wav2vec2",
            doStableLayerNorm: false
        )
        XCTAssertFalse(configStandard.doStableLayerNorm)

        // Test true variant
        let configStable = Wav2VecModelConfig(
            modelType: "wav2vec2",
            doStableLayerNorm: true
        )
        XCTAssertTrue(configStable.doStableLayerNorm)
    }

    func testFeatExtractNorm() throws {
        // Test "group" variant
        let configGroup = Wav2VecModelConfig(
            modelType: "wav2vec2",
            featExtractNorm: "group"
        )
        XCTAssertEqual(configGroup.featExtractNorm, "group")

        // Test "layer" variant
        let configLayer = Wav2VecModelConfig(
            modelType: "wav2vec2",
            featExtractNorm: "layer"
        )
        XCTAssertEqual(configLayer.featExtractNorm, "layer")
    }

    func testOptionalLMHead() throws {
        // Test without lm_head (vocab_size = nil)
        let configNoLM = Wav2VecModelConfig(
            modelType: "wav2vec2",
            vocabSize: nil
        )
        XCTAssertNil(configNoLM.vocabSize)

        // Test with lm_head (vocab_size present)
        let configWithLM = Wav2VecModelConfig(
            modelType: "wav2vec2",
            vocabSize: 32
        )
        XCTAssertEqual(configWithLM.vocabSize, 32)
    }

    func testDecodeFromJSON() throws {
        let json = """
        {
            "model_type": "wav2vec2",
            "conv_dim": [512, 512, 512, 512, 512, 512, 512],
            "conv_stride": [5, 2, 2, 2, 2, 2, 2],
            "conv_kernel": [10, 3, 3, 3, 3, 2, 2],
            "num_conv_pos_embeddings": 128,
            "num_conv_pos_embedding_groups": 16,
            "hidden_size": 1024,
            "num_hidden_layers": 24,
            "num_attention_heads": 16,
            "intermediate_size": 4096,
            "hidden_act": "gelu",
            "feat_extract_norm": "group",
            "do_stable_layer_norm": false,
            "layer_norm_eps": 1e-5
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let config = try decoder.decode(Wav2VecModelConfig.self, from: json)

        XCTAssertEqual(config.modelType, "wav2vec2")
        XCTAssertEqual(config.convDim.count, 7)
        XCTAssertEqual(config.convDim[0], 512)
        XCTAssertEqual(config.convStride[0], 5)
        XCTAssertEqual(config.convKernel[0], 10)
        XCTAssertEqual(config.hiddenSize, 1024)
        XCTAssertFalse(config.doStableLayerNorm)
    }
}
