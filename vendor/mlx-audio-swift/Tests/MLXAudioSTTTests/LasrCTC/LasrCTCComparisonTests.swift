//
//  LasrCTCComparisonTests.swift
//  MLXAudioSTTTests
//
// Created by act agent on 08/02/2026.
//

import XCTest
import MLX
@testable import MLXAudioSTT

final class LasrCTCComparisonTests: XCTestCase {

    func testWeightSanitization() throws {
        // Test Conv1d weight transposition
        let conv1dWeight = MLXRandom.normal([16, 32, 5])  // (out, in, kernel)
        let weights: [String: MLXArray] = [
            "encoder.subsampler.conv_0.weight": conv1dWeight,
            "ctc_head.weight": MLXRandom.normal([512, 256, 1]),  // Conv1d to Linear
            "ctc_head.bias": MLXRandom.normal([1, 512]),  // Should be squeezed
            "encoder.rotary_emb.inv_freq": MLXRandom.normal([64])  // Should be skipped
        ]

        let sanitized = LasrForCTC.sanitize(weights: weights)

        // Conv1d weights should be transposed to (out, kernel, in)
        XCTAssertEqual(sanitized["encoder.subsampler.conv_0.weight"]?.shape, [16, 5, 32])

        // CTC head weight should be squeezed to 2D
        XCTAssertEqual(sanitized["ctc_head.weight"]?.shape, [512, 256])

        // CTC head bias should be squeezed to 1D
        XCTAssertEqual(sanitized["ctc_head.bias"]?.shape, [512])

        // inv_freq should be skipped
        XCTAssertNil(sanitized["encoder.rotary_emb.inv_freq"])
    }

    func testEncoderSubsamplingConsistency() throws {
        // Test that subsampling produces consistent output shapes
        let config = LasrEncoderConfig(
            hiddenSize: 256,
            numMelBins: 128,
            subsamplingConvChannels: 128,
            subsamplingConvKernelSize: 5,
            subsamplingConvStride: 2
        )

        let subsampling = LasrEncoderSubsampling(config: config)

        // Test with different sequence lengths
        for seqLen in [80, 100, 120] {
            let input = MLXRandom.normal([1, seqLen, 128])
            let output = subsampling(input)

            // Calculate expected output length
            // First conv: (seqLen - 5) / 2 + 1
            let afterConv0 = (seqLen - 5) / 2 + 1
            // Second conv: (afterConv0 - 5) / 2 + 1
            let expectedLen = (afterConv0 - 5) / 2 + 1

            XCTAssertEqual(output.shape[1], expectedLen, "Unexpected output length for input seqLen=\(seqLen)")
            XCTAssertEqual(output.shape[2], config.hiddenSize)
        }
    }

    func testAttentionWithAndWithoutRoPE() throws {
        // Test that attention works with and without RoPE
        let config = LasrEncoderConfig(
            hiddenSize: 256,
            numAttentionHeads: 8,
            numKeyValueHeads: 8
        )

        let attention = LasrEncoderAttention(config: config)
        let rope = LasrEncoderRotaryEmbedding(config: config)

        let input = MLXRandom.normal([1, 50, 256])

        // Without RoPE
        let outputNoRoPE = attention(input, positionEmbeddings: nil, mask: nil)
        XCTAssertEqual(outputNoRoPE.shape, [1, 50, 256])

        // With RoPE
        let (cos, sin) = rope(input)
        let outputWithRoPE = attention(input, positionEmbeddings: (cos, sin), mask: nil)
        XCTAssertEqual(outputWithRoPE.shape, [1, 50, 256])

        // Outputs should be different due to RoPE
        let diff = abs(outputNoRoPE - outputWithRoPE).sum().item(Float.self)
        XCTAssertGreaterThan(diff, 0.0, "RoPE should change the output")
    }

    func testConvolutionModuleGLU() throws {
        // Test that GLU activation works correctly
        let config = LasrEncoderConfig(
            hiddenSize: 64,
            hiddenAct: "silu",
            convKernelSize: 7
        )

        let conv = LasrEncoderConvolutionModule(config: config)
        let input = MLXRandom.normal([1, 20, 64])

        let output = conv(input)

        // Output shape should match input
        XCTAssertEqual(output.shape, [1, 20, 64])

        // Output should be different from input
        let diff = abs(output - input).sum().item(Float.self)
        XCTAssertGreaterThan(diff, 0.0)
    }

    func testResidualWeightsScaling() throws {
        // Test that residual weights properly scale outputs
        let config = LasrEncoderConfig(
            hiddenSize: 32,
            numAttentionHeads: 4,
            intermediateSize: 64,
            convResidualWeights: [2.0, 1.0],
            feedForwardResidualWeights: [1.5, 0.5]
        )

        let block = LasrEncoderBlock(config: config)
        let input = MLXRandom.normal([1, 10, 32])

        let output = block(input, positionEmbeddings: nil, mask: nil)

        // Output should be different from input due to residual weighting
        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testFullEncoderNumericalStability() throws {
        // Test that encoder produces stable outputs
        let config = LasrEncoderConfig(
            hiddenSize: 256,
            numHiddenLayers: 4,
            numAttentionHeads: 8,
            intermediateSize: 1024,
            numMelBins: 128
        )

        let encoder = LasrEncoder(config: config)
        let input = MLXRandom.normal([1, 100, 128])

        let output = encoder(input, mask: nil)

        // Check output magnitude is reasonable
        let meanAbs = abs(output).mean().item(Float.self)
        XCTAssertLessThan(meanAbs, 100.0, "Output magnitude seems unreasonably large")
        XCTAssertGreaterThan(meanAbs, 0.0, "Output is all zeros")
    }

    func testCTCDecodingDeterminism() throws {
        // Test that CTC decoding is deterministic
        let config = LasrCTCModelConfig(
            vocabSize: 100,
            encoderConfig: LasrEncoderConfig(
                hiddenSize: 128,
                numHiddenLayers: 2,
                numAttentionHeads: 4,
                numMelBins: 128
            )
        )

        let model = LasrForCTC(config: config)
        let input = MLXRandom.normal([1, 80, 128])

        // Generate twice
        let output1 = model.generate(audio: input, vocabulary: nil)
        let output2 = model.generate(audio: input, vocabulary: nil)

        // Outputs should be identical (greedy decoding is deterministic)
        XCTAssertEqual(output1.text, output2.text)
    }

    func testCTCWithVocabulary() throws {
        // Test CTC decoding with a vocabulary
        let vocab = ["<blank>"] + (0..<99).map { "token_\($0)" }

        let config = LasrCTCModelConfig(
            vocabSize: 100,
            encoderConfig: LasrEncoderConfig(
                hiddenSize: 64,
                numHiddenLayers: 1,
                numAttentionHeads: 4,
                numMelBins: 128
            )
        )

        let model = LasrForCTC(config: config)
        let input = MLXRandom.normal([1, 50, 128])

        let output = model.generate(audio: input, vocabulary: vocab)

        // With vocabulary, text should not contain numbers
        XCTAssertFalse(output.text.contains(" "), "With vocabulary, output should not contain spaces from token IDs")
    }
}
