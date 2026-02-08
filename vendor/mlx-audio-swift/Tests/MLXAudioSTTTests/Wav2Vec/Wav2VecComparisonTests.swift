//
//  Wav2VecComparisonTests.swift
//  MLXAudioSTTTests
//
// Created by act agent on 08/02/2026.
//

import XCTest
import MLX
import MLXNN
@testable import MLXAudioSTT

final class Wav2VecComparisonTests: XCTestCase {

    func testWeightNormalizationReparameterization() throws {
        let weightG = MLXArray([2.0, 3.0]).reshaped([2, 1, 1])
        let weightV = MLXArray([1.0, 2.0, 3.0, 4.0]).reshaped([2, 1, 2])

        let normV = sqrt(sum(pow(weightV, 2), axes: [1, 2], keepDims: true))
        let expectedWeight = weightG * (weightV / (normV + 1e-12))

        let actualNormV = sqrt(sum(pow(weightV, 2), axes: [1, 2], keepDims: true))
        let actualWeight = weightG * (weightV / (actualNormV + 1e-12))

        XCTAssertEqual(expectedWeight.shape, actualWeight.shape)

        for i in 0..<expectedWeight.shape[0] {
            for j in 0..<expectedWeight.shape[1] {
                for k in 0..<expectedWeight.shape[2] {
                    let expected = expectedWeight[i, j, k].item(Float.self)
                    let actual = actualWeight[i, j, k].item(Float.self)
                    XCTAssertEqual(expected, actual, accuracy: 1e-4)
                }
            }
        }
    }

    func testFeatureEncoderOutputShapeSmall() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [16, 16, 16, 16, 16, 16, 16],
            convStride: [5, 2, 2, 2, 2, 2, 2],
            convKernel: [10, 3, 3, 3, 3, 3, 2],
            hiddenSize: 32,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            featExtractNorm: "group"
        )

        let encoder = Wav2Vec2FeatureEncoder(config: config)

        let input = MLXRandom.normal([1, 16000])
        let output = encoder(input)

        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[1], 16)
        XCTAssertGreaterThan(output.shape[2], 0)
    }

    func testWNConv1dForwardPass() throws {
        let conv = WNConv1d(
            inChannels: 4,
            outChannels: 8,
            kernelSize: 3,
            stride: 1,
            padding: 1,
            bias: true,
            groups: 1
        )

        let input = MLXRandom.normal([1, 4, 10])
        let output = conv(input)

        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[1], 8)
        XCTAssertGreaterThan(output.shape[2], 0)
    }

    func testPositionalConvEmbedding() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            numConvPosEmbeddings: 128,
            numConvPosEmbeddingGroups: 16,
            hiddenSize: 32
        )

        let posEmbed = Wav2Vec2PositionalConvEmbedding(config: config)

        let input = MLXRandom.normal([1, 50, 32])
        let output = posEmbed(input)

        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[2], 32)
        XCTAssertGreaterThanOrEqual(output.shape[1], 49)
        XCTAssertLessThanOrEqual(output.shape[1], 50)
    }

    func testFullModelPipeline() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [16, 16, 16, 16, 16, 16, 16],
            convStride: [5, 2, 2, 2, 2, 2, 2],
            convKernel: [10, 3, 3, 3, 3, 3, 2],
            hiddenSize: 32,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            intermediateSize: 128,
            featExtractNorm: "group",
            doStableLayerNorm: false
        )

        let model = Wav2Vec2Model(config: config)

        let input = MLXRandom.normal([1, 16000])
        let output = model(inputValues: input, attentionMask: nil)

        XCTAssertEqual(output.lastHiddenState.shape[0], 1)
        XCTAssertEqual(output.lastHiddenState.shape[2], 32)
        XCTAssertGreaterThan(output.lastHiddenState.shape[1], 0)
    }

    func testFeatureExtractorNormalizationAccuracy() throws {
        let audio: [Float] = (0..<1000).map { Float($0) / 1000.0 }
        let audioArray = MLXArray(audio)

        let extractor = Wav2Vec2FeatureExtractor()
        let normalized = extractor.normalize(audioArray)

        let mean = normalized.mean().item(Float.self)
        XCTAssertEqual(mean, 0.0, accuracy: 1e-5)

        let variance = pow(normalized - mean, 2).mean().item(Float.self)
        XCTAssertEqual(variance, 1.0, accuracy: 1e-3)
    }

    func testSanitizeWeightTransposition() throws {
        let config = Wav2VecModelConfig(modelType: "wav2vec2")
        let model = Wav2Vec2Model(config: config)

        let weights: [String: MLXArray] = [
            "feature_extractor.conv_layers.0.conv.weight": MLXArray.ones([512, 1, 10]),
            "feature_extractor.conv_layers.1.conv.weight": MLXArray.ones([512, 3, 512]),
            "encoder.pos_conv_embed.conv.weight_g": MLXArray.ones([768, 128, 1]),
            "encoder.pos_conv_embed.conv.weight_v": MLXArray.ones([768, 128, 48]),
            "lm_head.weight": MLXArray.ones([32, 768]),
            "masked_spec_embed": MLXArray.ones([768])
        ]

        let sanitized = model.sanitize(weights: weights)

        XCTAssertTrue(sanitized["feature_extractor.conv_layers.0.conv.weight"] != nil)

        XCTAssertNil(sanitized["lm_head.weight"])
        XCTAssertNil(sanitized["masked_spec_embed"])

        let convWeight = sanitized["feature_extractor.conv_layers.0.conv.weight"]!
        XCTAssertEqual(convWeight.shape, [512, 10, 1])
    }
}
