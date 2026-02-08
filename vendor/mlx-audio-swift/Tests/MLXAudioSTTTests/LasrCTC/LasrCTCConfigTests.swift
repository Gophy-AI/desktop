//
//  LasrCTCConfigTests.swift
//  MLXAudioSTTTests
//
// Created by act agent on 08/02/2026.
//

import XCTest
@testable import MLXAudioSTT

final class LasrCTCConfigTests: XCTestCase {

    func testLasrEncoderConfigCodableRoundTrip() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 512,
            numHiddenLayers: 17,
            numAttentionHeads: 8,
            numKeyValueHeads: 8,
            intermediateSize: 2048,
            hiddenAct: "silu",
            convKernelSize: 32,
            convolutionBias: false,
            numMelBins: 128,
            subsamplingConvChannels: 256,
            subsamplingConvKernelSize: 5,
            subsamplingConvStride: 2,
            dropout: 0.1,
            attentionDropout: 0.1,
            activationDropout: 0.1,
            dropoutPositions: 0.0,
            layerdrop: 0.1,
            layerNormEps: 1e-6,
            batchNormMomentum: 0.01,
            initializerRange: 0.02,
            maxPositionEmbeddings: 10000,
            attentionBias: false,
            ropeTheta: 10000.0,
            ropeType: "default",
            convResidualWeights: [2.0, 1.0],
            feedForwardResidualWeights: [1.5, 0.5]
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        // Decode from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LasrEncoderConfig.self, from: data)

        // Verify all values match
        XCTAssertEqual(decoded.hiddenSize, config.hiddenSize)
        XCTAssertEqual(decoded.numHiddenLayers, config.numHiddenLayers)
        XCTAssertEqual(decoded.numAttentionHeads, config.numAttentionHeads)
        XCTAssertEqual(decoded.numKeyValueHeads, config.numKeyValueHeads)
        XCTAssertEqual(decoded.intermediateSize, config.intermediateSize)
        XCTAssertEqual(decoded.hiddenAct, config.hiddenAct)
        XCTAssertEqual(decoded.convKernelSize, config.convKernelSize)
        XCTAssertEqual(decoded.convolutionBias, config.convolutionBias)
        XCTAssertEqual(decoded.numMelBins, config.numMelBins)
        XCTAssertEqual(decoded.subsamplingConvChannels, config.subsamplingConvChannels)
        XCTAssertEqual(decoded.subsamplingConvKernelSize, config.subsamplingConvKernelSize)
        XCTAssertEqual(decoded.subsamplingConvStride, config.subsamplingConvStride)
        XCTAssertEqual(decoded.dropout, config.dropout)
        XCTAssertEqual(decoded.attentionDropout, config.attentionDropout)
        XCTAssertEqual(decoded.activationDropout, config.activationDropout)
        XCTAssertEqual(decoded.dropoutPositions, config.dropoutPositions)
        XCTAssertEqual(decoded.layerdrop, config.layerdrop)
        XCTAssertEqual(decoded.layerNormEps, config.layerNormEps)
        XCTAssertEqual(decoded.batchNormMomentum, config.batchNormMomentum)
        XCTAssertEqual(decoded.initializerRange, config.initializerRange)
        XCTAssertEqual(decoded.maxPositionEmbeddings, config.maxPositionEmbeddings)
        XCTAssertEqual(decoded.attentionBias, config.attentionBias)
        XCTAssertEqual(decoded.ropeTheta, config.ropeTheta)
        XCTAssertEqual(decoded.ropeType, config.ropeType)
        XCTAssertEqual(decoded.convResidualWeights, config.convResidualWeights)
        XCTAssertEqual(decoded.feedForwardResidualWeights, config.feedForwardResidualWeights)
    }

    func testLasrCTCModelConfigCodableRoundTrip() throws {
        let encoderConfig = LasrEncoderConfig(
            hiddenSize: 512,
            numHiddenLayers: 17,
            numAttentionHeads: 8,
            numKeyValueHeads: 8,
            intermediateSize: 2048,
            ropeTheta: 10000.0
        )

        let modelConfig = LasrCTCModelConfig(
            vocabSize: 512,
            encoderConfig: encoderConfig,
            ctcLossReduction: "mean",
            ctcZeroInfinity: true,
            padTokenId: 0,
            initializerRange: 0.02,
            modelType: "lasr_ctc"
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(modelConfig)

        // Decode from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LasrCTCModelConfig.self, from: data)

        // Verify all values match
        XCTAssertEqual(decoded.vocabSize, modelConfig.vocabSize)
        XCTAssertEqual(decoded.encoderConfig.hiddenSize, modelConfig.encoderConfig.hiddenSize)
        XCTAssertEqual(decoded.encoderConfig.numHiddenLayers, modelConfig.encoderConfig.numHiddenLayers)
        XCTAssertEqual(decoded.encoderConfig.ropeTheta, modelConfig.encoderConfig.ropeTheta)
        XCTAssertEqual(decoded.ctcLossReduction, modelConfig.ctcLossReduction)
        XCTAssertEqual(decoded.ctcZeroInfinity, modelConfig.ctcZeroInfinity)
        XCTAssertEqual(decoded.padTokenId, modelConfig.padTokenId)
        XCTAssertEqual(decoded.initializerRange, modelConfig.initializerRange)
        XCTAssertEqual(decoded.modelType, modelConfig.modelType)
    }

    func testNestedEncoderConfigParsing() throws {
        let json = """
        {
            "vocab_size": 512,
            "encoder_config": {
                "hidden_size": 512,
                "num_hidden_layers": 17,
                "num_attention_heads": 8,
                "num_key_value_heads": 8,
                "intermediate_size": 2048,
                "rope_theta": 10000.0
            },
            "model_type": "lasr_ctc"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(LasrCTCModelConfig.self, from: data)

        XCTAssertEqual(config.vocabSize, 512)
        XCTAssertEqual(config.encoderConfig.hiddenSize, 512)
        XCTAssertEqual(config.encoderConfig.numHiddenLayers, 17)
        XCTAssertEqual(config.encoderConfig.numAttentionHeads, 8)
        XCTAssertEqual(config.encoderConfig.numKeyValueHeads, 8)
        XCTAssertEqual(config.encoderConfig.intermediateSize, 2048)
        XCTAssertEqual(config.encoderConfig.ropeTheta, 10000.0)
        XCTAssertEqual(config.modelType, "lasr_ctc")
    }

    func testDefaultValues() throws {
        let config = LasrEncoderConfig()

        XCTAssertEqual(config.hiddenSize, 512)
        XCTAssertEqual(config.numHiddenLayers, 17)
        XCTAssertEqual(config.numAttentionHeads, 8)
        XCTAssertEqual(config.numKeyValueHeads, 8)
        XCTAssertEqual(config.intermediateSize, 2048)
        XCTAssertEqual(config.hiddenAct, "silu")
        XCTAssertEqual(config.convKernelSize, 32)
        XCTAssertEqual(config.convolutionBias, false)
        XCTAssertEqual(config.numMelBins, 128)
        XCTAssertEqual(config.subsamplingConvChannels, 256)
        XCTAssertEqual(config.ropeTheta, 10000.0)
        XCTAssertEqual(config.convResidualWeights, [2.0, 1.0])
        XCTAssertEqual(config.feedForwardResidualWeights, [1.5, 0.5])
    }
}
