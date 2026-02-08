//
//  VoxtralLayerTests.swift
//  MLXAudioSTTTests
//
// Tests for Voxtral encoder layers and projector

import XCTest
import MLX
import MLXNN
@testable import MLXAudioSTT

final class VoxtralLayerTests: XCTestCase {

    func testAttentionOutputShape() throws {
        // Small config for testing
        var config = VoxtralAudioConfig()
        config.dModel = 64
        config.encoderAttentionHeads = 4
        config.encoderFfnDim = 256

        let attention = VoxtralAttention(config: config)

        let batchSize = 2
        let seqLen = 10
        let hiddenStates = MLXRandom.uniform(low: 0, high: 1, [batchSize, seqLen, config.dModel])

        let output = attention(hiddenStates)

        XCTAssertEqual(output.ndim, 3)
        XCTAssertEqual(output.shape[0], batchSize)
        XCTAssertEqual(output.shape[1], seqLen)
        XCTAssertEqual(output.shape[2], config.dModel)
    }

    func testEncoderLayerOutputShape() throws {
        var config = VoxtralAudioConfig()
        config.dModel = 64
        config.encoderAttentionHeads = 4
        config.encoderFfnDim = 256

        let layer = VoxtralEncoderLayer(config: config)

        let batchSize = 2
        let seqLen = 10
        let hiddenStates = MLXRandom.uniform(low: 0, high: 1, [batchSize, seqLen, config.dModel])

        let output = layer(hiddenStates)

        XCTAssertEqual(output.ndim, 3)
        XCTAssertEqual(output.shape[0], batchSize)
        XCTAssertEqual(output.shape[1], seqLen)
        XCTAssertEqual(output.shape[2], config.dModel)
    }

    func testEncoderDownsampling() throws {
        // Test that encoder downsamples by 2x due to stride-2 Conv1d
        var config = VoxtralAudioConfig()
        config.dModel = 64
        config.encoderAttentionHeads = 4
        config.encoderFfnDim = 256
        config.numMelBins = 128
        config.maxSourcePositions = 100
        config.encoderLayers = 2

        let encoder = VoxtralEncoder(config: config)

        let batchSize = 1
        let seqLen = 20
        let inputFeatures = MLXRandom.uniform(low: 0, high: 1, [batchSize, config.numMelBins, seqLen])

        let output = encoder(inputFeatures)

        // Conv2 has stride 2, so sequence length should be downsampled
        let expectedSeqLen = seqLen / 2

        XCTAssertEqual(output.ndim, 3)
        XCTAssertEqual(output.shape[0], batchSize)
        XCTAssertEqual(output.shape[1], expectedSeqLen)
        XCTAssertEqual(output.shape[2], config.dModel)
    }

    func testMultiModalProjectorOutputShape() throws {
        var audioConfig = VoxtralAudioConfig()
        audioConfig.intermediateSize = 256

        var textConfig = VoxtralTextConfig()
        textConfig.hiddenSize = 512

        let modelConfig = VoxtralModelConfig(
            audioConfig: audioConfig,
            textConfig: textConfig
        )

        let projector = VoxtralMultiModalProjector(config: modelConfig)

        let batchSize = 2
        let seqLen = 10
        let audioFeatures = MLXRandom.uniform(low: 0, high: 1, [batchSize, seqLen, audioConfig.intermediateSize])

        let output = projector(audioFeatures)

        XCTAssertEqual(output.ndim, 3)
        XCTAssertEqual(output.shape[0], batchSize)
        XCTAssertEqual(output.shape[1], seqLen)
        XCTAssertEqual(output.shape[2], textConfig.hiddenSize)
    }

    func testEncoderWithLayerNorm() throws {
        var config = VoxtralAudioConfig()
        config.dModel = 64
        config.encoderAttentionHeads = 4
        config.encoderFfnDim = 256
        config.numMelBins = 128
        config.maxSourcePositions = 100
        config.encoderLayers = 2

        let encoder = VoxtralEncoder(config: config)

        let batchSize = 1
        let seqLen = 20
        let inputFeatures = MLXRandom.uniform(low: 0, high: 1, [batchSize, config.numMelBins, seqLen])

        let output = encoder(inputFeatures)

        // Check that output exists and has correct shape
        XCTAssertEqual(output.shape[2], config.dModel)

        // Check that layer norm was applied (output should have reasonable values)
        let mean = output.mean().item(Float.self)
        XCTAssertTrue(abs(mean) < 10.0, "Mean should be reasonable after layer norm")
    }

    func testConv1dWeightTransposition() throws {
        // Test that sanitize transposes Conv1d weights correctly
        let model = VoxtralModel(config: VoxtralModelConfig())

        // Create a mock Conv1d weight with wrong shape
        let wrongShape = MLXRandom.uniform(low: 0, high: 1, [64, 128, 3])  // (out, in, kernel)
        let weights = [
            "audio_tower.conv1.weight": wrongShape
        ]

        let sanitized = model.sanitize(weights: weights)

        // Should be transposed to (out, kernel, in)
        if let transposed = sanitized["audio_tower.conv1.weight"] {
            XCTAssertEqual(transposed.shape[0], 64)
            XCTAssertEqual(transposed.shape[1], 3)
            XCTAssertEqual(transposed.shape[2], 128)
        } else {
            XCTFail("Sanitized weights should contain conv1 weight")
        }
    }

    func testConv1dWeightNoTransposition() throws {
        // Test that sanitize does NOT transpose if shape is already correct
        let model = VoxtralModel(config: VoxtralModelConfig())

        // Create a mock Conv1d weight with correct shape (kernel < in_channels)
        let correctShape = MLXRandom.uniform(low: 0, high: 1, [64, 3, 128])  // (out, kernel, in)
        let weights = [
            "audio_tower.conv1.weight": correctShape
        ]

        let sanitized = model.sanitize(weights: weights)

        // Should NOT be transposed
        if let result = sanitized["audio_tower.conv1.weight"] {
            XCTAssertEqual(result.shape[0], 64)
            XCTAssertEqual(result.shape[1], 3)
            XCTAssertEqual(result.shape[2], 128)
        } else {
            XCTFail("Sanitized weights should contain conv1 weight")
        }
    }
}
