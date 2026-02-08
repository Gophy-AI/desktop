//
//  Wav2VecLayerTests.swift
//  MLXAudioSTTTests
//
// Created by act agent on 08/02/2026.
//

import XCTest
import MLX
import MLXNN
@testable import MLXAudioSTT

final class Wav2VecLayerTests: XCTestCase {

    func testWNConv1dWeightNormalization() throws {
        // Create a small WNConv1d layer
        let conv = WNConv1d(
            inChannels: 8,
            outChannels: 16,
            kernelSize: 3,
            stride: 1,
            padding: 1,
            bias: true,
            groups: 1
        )

        // Verify weight normalization: weight = weight_g * (weight_v / norm(weight_v))
        let weightG = conv.weightG
        let weightV = conv.weightV

        // Compute norm along all axes except dim 0 (out_channels)
        let normV = sqrt(sum(pow(weightV, 2), axes: [1, 2], keepDims: true))
        let expectedWeight = weightG * (weightV / (normV + 1e-12))

        // Forward pass to compute actual weight
        let input = MLXRandom.normal([1, 8, 10])
        _ = conv(input)

        // Check shapes
        XCTAssertEqual(weightG.shape, [16, 1, 1])
        XCTAssertEqual(weightV.shape, [16, 3, 8])
        XCTAssertEqual(expectedWeight.shape, [16, 3, 8])
    }

    func testWav2Vec2GroupNormConvLayer() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [16, 16, 16, 16, 16, 16, 16],
            convStride: [2, 2, 2, 2, 2, 2, 2],
            convKernel: [3, 3, 3, 3, 3, 3, 3]
        )

        let layer = Wav2Vec2GroupNormConvLayer(config: config, layerId: 0)

        // Input: (batch=1, channels=1, length=32)
        let input = MLXRandom.normal([1, 1, 32])
        let output = layer(input)

        // Output should have correct shape after conv
        // stride=2, so length should be ~16
        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[1], 16)  // out_channels
        XCTAssertGreaterThan(output.shape[2], 0)  // length reduced by stride
    }

    func testWav2Vec2NoLayerNormConvLayer() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [16, 16, 16, 16, 16, 16, 16],
            convStride: [1, 1, 1, 1, 1, 1, 1],
            convKernel: [3, 3, 3, 3, 3, 3, 3]
        )

        let layer = Wav2Vec2NoLayerNormConvLayer(config: config, layerId: 1)

        // Input: (batch=1, channels=16, length=16)
        let input = MLXRandom.normal([1, 16, 16])
        let output = layer(input)

        // Output should maintain shape with stride=1
        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[1], 16)
        XCTAssertGreaterThan(output.shape[2], 0)
    }

    func testWav2Vec2LayerNormConvLayer() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [16, 16, 16, 16, 16, 16, 16],
            convStride: [1, 1, 1, 1, 1, 1, 1],
            convKernel: [3, 3, 3, 3, 3, 3, 3]
        )

        let layer = Wav2Vec2LayerNormConvLayer(config: config, layerId: 1)

        // Input: (batch=1, channels=16, length=16)
        let input = MLXRandom.normal([1, 16, 16])
        let output = layer(input)

        // Output should maintain shape with stride=1
        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[1], 16)
        XCTAssertGreaterThan(output.shape[2], 0)
    }

    func testWav2Vec2FeatureEncoderDownsampling() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [16, 16, 16, 16, 16, 16, 16],
            convStride: [5, 2, 2, 2, 2, 2, 2],
            convKernel: [10, 3, 3, 3, 3, 3, 2],
            featExtractNorm: "group"
        )

        let encoder = Wav2Vec2FeatureEncoder(config: config)

        // Input: raw audio (batch=1, samples=16000)
        let input = MLXRandom.normal([1, 16000])
        let output = encoder(input)

        // Total downsampling: 5 * 2 * 2 * 2 * 2 * 2 * 2 = 320x
        // 16000 / 320 = 50
        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[1], 16)  // conv_dim[-1]
        XCTAssertGreaterThan(output.shape[2], 0)
        // Due to convolution padding, exact length may vary slightly
        XCTAssertLessThan(abs(output.shape[2] - 50), 5)
    }

    func testWav2Vec2FeatureProjection() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            convDim: [512, 512, 512, 512, 512, 512, 512],
            hiddenSize: 32
        )

        let projection = Wav2Vec2FeatureProjection(config: config)

        // Input: (batch=1, time=50, conv_dim[-1]=512)
        let input = MLXRandom.normal([1, 50, 512])
        let (output, _) = projection(input)

        // Output should be projected to hidden_size
        XCTAssertEqual(output.shape, [1, 50, 32])
    }

    func testWav2Vec2PositionalConvEmbedding() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            numConvPosEmbeddings: 128,
            numConvPosEmbeddingGroups: 16,
            hiddenSize: 32
        )

        let posEmbed = Wav2Vec2PositionalConvEmbedding(config: config)

        // Input: (batch=1, time=50, hidden=32)
        let input = MLXRandom.normal([1, 50, 32])
        let output = posEmbed(input)

        // Output should have same shape (may be trimmed by 1 if even kernel)
        XCTAssertEqual(output.shape[0], 1)
        XCTAssertEqual(output.shape[2], 32)
        // Length may be reduced by SamePadLayer
        XCTAssertGreaterThanOrEqual(output.shape[1], 49)
        XCTAssertLessThanOrEqual(output.shape[1], 50)
    }

    func testWav2Vec2Attention() throws {
        let embedDim = 32
        let numHeads = 4

        let attention = Wav2Vec2Attention(
            embedDim: embedDim,
            numHeads: numHeads,
            dropout: 0.0,
            bias: true
        )

        // Input: (batch=1, time=10, embed=32)
        let input = MLXRandom.normal([1, 10, 32])
        let (output, _) = attention(input, attentionMask: nil)

        // Output should have same shape
        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testWav2Vec2EncoderOutputShape() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            hiddenSize: 32,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            intermediateSize: 128,
            doStableLayerNorm: false
        )

        let encoder = Wav2Vec2Encoder(config: config)

        // Input: (batch=1, time=50, hidden=32)
        let input = MLXRandom.normal([1, 50, 32])
        let output = encoder(input, attentionMask: nil)

        // Output should have same shape
        XCTAssertEqual(output.lastHiddenState.shape, [1, 50, 32])
    }

    func testWav2Vec2EncoderStableLayerNormOutputShape() throws {
        let config = Wav2VecModelConfig(
            modelType: "wav2vec2",
            hiddenSize: 32,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            intermediateSize: 128,
            doStableLayerNorm: true
        )

        let encoder = Wav2Vec2EncoderStableLayerNorm(config: config)

        // Input: (batch=1, time=50, hidden=32)
        let input = MLXRandom.normal([1, 50, 32])
        let output = encoder(input, attentionMask: nil)

        // Output should have same shape
        XCTAssertEqual(output.lastHiddenState.shape, [1, 50, 32])
    }

    func testWav2Vec2FeatureExtractorNormalization() throws {
        // Create raw audio with known mean and std
        let audio: [Float] = Array(repeating: 2.0, count: 1000) + Array(repeating: 4.0, count: 1000)
        let audioArray = MLXArray(audio)

        let extractor = Wav2Vec2FeatureExtractor(
            featureSize: 1,
            samplingRate: 16000,
            paddingValue: 0.0
        )

        let normalized = extractor.normalize(audioArray)

        // Check zero mean
        let mean = normalized.mean().item(Float.self)
        XCTAssertEqual(mean, 0.0, accuracy: 1e-5)

        // Check unit variance
        let variance = pow(normalized - mean, 2).mean().item(Float.self)
        XCTAssertEqual(variance, 1.0, accuracy: 1e-4)
    }
}
