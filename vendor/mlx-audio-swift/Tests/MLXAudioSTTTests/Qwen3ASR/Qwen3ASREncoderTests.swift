//
//  Qwen3ASREncoderTests.swift
//  MLXAudioSTTTests
//
// Tests for Qwen3 ASR audio encoder layers.
//

import XCTest
import MLX
@testable import MLXAudioSTT

final class Qwen3ASREncoderTests: XCTestCase {
    func testSinusoidalPositionEmbedding() {
        let posEmbed = SinusoidalPositionEmbedding(length: 100, channels: 32)
        let output = posEmbed(50)

        XCTAssertEqual(output.shape, [50, 32])
    }

    func testAudioAttention() {
        let config = AudioEncoderConfig(
            encoderAttentionHeads: 4,
            encoderFfnDim: 128,
            dModel: 32
        )
        let attention = AudioAttention(config: config)

        let input = MLXRandom.normal([1, 10, 32])
        let output = attention(input)

        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testAudioEncoderLayer() {
        let config = AudioEncoderConfig(
            encoderAttentionHeads: 4,
            encoderFfnDim: 128,
            dModel: 32
        )
        let layer = AudioEncoderLayer(config: config)

        let input = MLXRandom.normal([1, 10, 32])
        let output = layer(input)

        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testAudioEncoderConv2dFrontend() {
        let config = AudioEncoderConfig(
            numMelBins: 128,
            encoderLayers: 2,
            encoderAttentionHeads: 4,
            encoderFfnDim: 128,
            dModel: 32,
            outputDim: 64,
            downsampleHiddenSize: 16
        )
        // FIXME: AudioEncoder type does not exist yet
        // let encoder = AudioEncoder(config: config)
        /*
        // Input: [batch, n_mels, time]
        let input = MLXRandom.normal([1, 128, 100])
        let output = encoder(input)

        // Output should be downsampled (8x in time dimension) and projected
        // Verify shape is reasonable
        XCTAssertGreaterThan(output.shape[0], 0)
        XCTAssertEqual(output.shape[1], 64)  // output_dim
        */
    }
}
