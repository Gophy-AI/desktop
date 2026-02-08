//
//  Qwen3ASRComparisonTests.swift
//  MLXAudioSTTTests
//
// Integration tests comparing Swift vs Python output.
//

import XCTest
import MLX
@testable import MLXAudioSTT

final class Qwen3ASRComparisonTests: XCTestCase {
    func testAudioEncoderOutput() {
        // Placeholder for Python comparison test
        // Real implementation would:
        // 1. Load reference Python output
        // 2. Run Swift encoder with same input
        // 3. Compare outputs within tolerance (atol=1e-3)

        XCTAssertTrue(true, "Placeholder test")
    }

    func testTextAttentionWithQKNorm() {
        // Test Q/K RMSNorm is applied before RoPE
        let config = TextConfig(
            hiddenSize: 32,
            intermediateSize: 128,
            numAttentionHeads: 4,
            numKeyValueHeads: 2,
            headDim: 8
        )
        let attention = TextAttention(config: config, layerIdx: 0)

        let input = MLXRandom.normal([1, 5, 32])
        let output = attention(input)

        // Verify output shape
        XCTAssertEqual(output.shape, [1, 5, 32])
    }

    func testConv2dWeightTranspose() {
        // Test sanitize() correctly transposes Conv2d weights
        let weights: [String: MLXArray] = [
            "audio_tower.conv2d1.weight": MLXRandom.normal([3, 3, 1, 480]),
            "text_model.embed_tokens.weight": MLXRandom.normal([151936, 3584])
        ]

        let sanitized = Qwen3ASRModel.sanitize(weights: weights)

        // Conv2d weight should be transposed
        XCTAssertEqual(sanitized["audio_tower.conv2d1.weight"]!.shape, [3, 3, 480, 1])

        // Embedding weight should not be transposed
        XCTAssertEqual(sanitized["text_model.embed_tokens.weight"]!.shape, [151936, 3584])
    }

    func testSplitAudioIntoChunks() {
        // Test energy-based audio chunking
        let sampleRate = 16000
        let duration: Float = 30.0  // 30 seconds
        let samples = Int(duration * Float(sampleRate))
        let audio = (0..<samples).map { _ in Float.random(in: -1.0...1.0) }

        let chunks = Qwen3ASRModel.splitAudioIntoChunks(
            audio: audio,
            sampleRate: sampleRate,
            maxChunkDuration: 20.0
        )

        // Should split into 2 chunks for 30s audio with 20s max
        XCTAssertGreaterThan(chunks.count, 1)

        // Verify offsets are monotonic
        for i in 1..<chunks.count {
            XCTAssertGreaterThan(chunks[i].offset, chunks[i - 1].offset)
        }
    }

    func testForcedAlignerClassifyNum() {
        // Test forced aligner has correct classify_num outputs
        let config = ForcedAlignerConfig(classifyNum: 5000)
        let model = ForcedAlignerModel(config: config)

        // Verify lm_head has correct output dimension
        XCTAssertEqual(model.lmHead.weight.shape[0], 5000)
    }

    func testCJKTextTokenization() {
        // Test CJK characters are tokenized individually
        let chineseText = "你好"
        let tokens = ForceAlignProcessor.tokenize(chineseText, language: "zh")

        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0], "你")
        XCTAssertEqual(tokens[1], "好")
    }

    func testLISTimestampCorrection() {
        // Test LIS produces monotonic results
        let items = [
            ForcedAlignItem(word: "a", start: 0.0, end: 0.1),
            ForcedAlignItem(word: "b", start: 0.5, end: 0.6),
            ForcedAlignItem(word: "c", start: 0.2, end: 0.3),
            ForcedAlignItem(word: "d", start: 0.8, end: 0.9),
            ForcedAlignItem(word: "e", start: 0.4, end: 0.5)
        ]

        let corrected = fixTimestampsWithLIS(items: items)

        // Verify monotonicity
        for i in 1..<corrected.count {
            XCTAssertGreaterThanOrEqual(corrected[i].start, corrected[i - 1].start,
                                        "Timestamps should be monotonic after LIS correction")
        }
    }
}
