//
//  LasrCTCLayerTests.swift
//  MLXAudioSTTTests
//
// Created by act agent on 08/02/2026.
//

import XCTest
import MLX
@testable import MLXAudioSTT

final class LasrCTCLayerTests: XCTestCase {

    func testRotaryEmbeddingShape() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            ropeTheta: 10000.0
        )

        let rope = LasrEncoderRotaryEmbedding(config: config)
        let batchSize = 2
        let seqLen = 10
        let numHeads = 4
        let headDim = 32 / 4

        let input = MLXRandom.normal([batchSize, seqLen, numHeads, headDim])
        let (cos, sin) = rope(input)

        // cos and sin should be [1, seqLen, 1, headDim]
        XCTAssertEqual(cos.shape, [1, seqLen, 1, headDim])
        XCTAssertEqual(sin.shape, [1, seqLen, 1, headDim])
    }

    func testSubsamplingDownsampling() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numMelBins: 128,
            subsamplingConvChannels: 16,
            subsamplingConvKernelSize: 5,
            subsamplingConvStride: 2
        )

        let subsampling = LasrEncoderSubsampling(config: config)

        let batchSize = 2
        let seqLen = 100
        let input = MLXRandom.normal([batchSize, seqLen, 128])

        let output = subsampling(input)

        // Each Conv1d with stride 2 halves the sequence length
        // Two Conv1d layers: seqLen -> seqLen/2 -> seqLen/4 (approximately, accounting for kernel size)
        // With kernel_size=5, stride=2, no padding:
        // out_len = (in_len - kernel_size) / stride + 1
        // First conv: (100 - 5) / 2 + 1 = 48
        // Second conv: (48 - 5) / 2 + 1 = 22
        let expectedSeqLen = 22

        XCTAssertEqual(output.shape[0], batchSize)
        XCTAssertEqual(output.shape[1], expectedSeqLen)
        XCTAssertEqual(output.shape[2], config.hiddenSize)
    }

    func testAttentionOutputShape() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numAttentionHeads: 4,
            numKeyValueHeads: 4,
            attentionBias: false
        )

        let attention = LasrEncoderAttention(config: config)

        let batchSize = 2
        let seqLen = 10
        let input = MLXRandom.normal([batchSize, seqLen, 32])

        let output = attention(input, positionEmbeddings: nil, mask: nil)

        XCTAssertEqual(output.shape, [batchSize, seqLen, config.hiddenSize])
    }

    func testAttentionWithRoPE() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numAttentionHeads: 4,
            numKeyValueHeads: 4,
            ropeTheta: 10000.0
        )

        let attention = LasrEncoderAttention(config: config)
        let rope = LasrEncoderRotaryEmbedding(config: config)

        let batchSize = 2
        let seqLen = 10
        let input = MLXRandom.normal([batchSize, seqLen, 32])

        let (cos, sin) = rope(input)
        let output = attention(input, positionEmbeddings: (cos, sin), mask: nil)

        XCTAssertEqual(output.shape, [batchSize, seqLen, config.hiddenSize])
    }

    func testAttentionGQA() throws {
        // Test Grouped Query Attention with different num_key_value_heads
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numAttentionHeads: 8,
            numKeyValueHeads: 4  // GQA: 8 query heads, 4 key/value heads
        )

        let attention = LasrEncoderAttention(config: config)

        let batchSize = 2
        let seqLen = 10
        let input = MLXRandom.normal([batchSize, seqLen, 32])

        let output = attention(input, positionEmbeddings: nil, mask: nil)

        XCTAssertEqual(output.shape, [batchSize, seqLen, config.hiddenSize])
    }

    func testConvolutionModuleShape() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            convKernelSize: 7,
            convolutionBias: false
        )

        let conv = LasrEncoderConvolutionModule(config: config)

        let batchSize = 2
        let seqLen = 20
        let input = MLXRandom.normal([batchSize, seqLen, 32])

        let output = conv(input)

        // Convolution module should preserve sequence length and hidden size
        XCTAssertEqual(output.shape, [batchSize, seqLen, config.hiddenSize])
    }

    func testFeedForwardOutputShape() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            intermediateSize: 64,
            hiddenAct: "silu"
        )

        let ff = LasrEncoderFeedForward(config: config)

        let batchSize = 2
        let seqLen = 10
        let input = MLXRandom.normal([batchSize, seqLen, 32])

        let output = ff(input)

        XCTAssertEqual(output.shape, [batchSize, seqLen, config.hiddenSize])
    }

    func testEncoderBlockWithResidualWeights() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numAttentionHeads: 4,
            intermediateSize: 64,
            convKernelSize: 7,
            convResidualWeights: [2.0, 1.0],
            feedForwardResidualWeights: [1.5, 0.5]
        )

        let block = LasrEncoderBlock(config: config)
        let rope = LasrEncoderRotaryEmbedding(config: config)

        let batchSize = 2
        let seqLen = 10
        let input = MLXRandom.normal([batchSize, seqLen, 32])

        let (cos, sin) = rope(input)
        let output = block(input, positionEmbeddings: (cos, sin), mask: nil)

        XCTAssertEqual(output.shape, [batchSize, seqLen, config.hiddenSize])
    }

    func testEncoderFullPipeline() throws {
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            intermediateSize: 64,
            numMelBins: 128,
            subsamplingConvChannels: 16
        )

        let encoder = LasrEncoder(config: config)

        let batchSize = 2
        let seqLen = 100
        let input = MLXRandom.normal([batchSize, seqLen, 128])

        let output = encoder(input, mask: nil)

        // After subsampling (4x downsampling), sequence length should be ~22
        let expectedSeqLen = 22
        XCTAssertEqual(output.shape[0], batchSize)
        XCTAssertEqual(output.shape[1], expectedSeqLen)
        XCTAssertEqual(output.shape[2], config.hiddenSize)
    }

    func testCTCGreedyDecoding() throws {
        // Create a simple model for testing
        let config = LasrCTCModelConfig(
            vocabSize: 50,
            encoderConfig: LasrEncoderConfig(
                hiddenSize: 32,
                numHiddenLayers: 1,
                numAttentionHeads: 4,
                numMelBins: 128
            )
        )

        let model = LasrForCTC(config: config)

        let batchSize = 1
        let seqLen = 100
        let input = MLXRandom.normal([batchSize, seqLen, 128])

        let logits = model(input)

        // Logits should have shape [batch, downsampled_seq_len, vocab_size]
        XCTAssertEqual(logits.shape[0], batchSize)
        XCTAssertEqual(logits.shape[2], config.vocabSize)

        // Generate output (without vocabulary for now)
        let output = model.generate(audio: input, vocabulary: nil)

        // Should produce some output
        XCTAssertFalse(output.text.isEmpty)
    }
}
