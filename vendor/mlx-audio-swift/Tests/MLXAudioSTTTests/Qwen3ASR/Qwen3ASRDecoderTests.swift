//
//  Qwen3ASRDecoderTests.swift
//  MLXAudioSTTTests
//
// Tests for Qwen3 ASR text decoder layers.
//

import XCTest
import MLX
import MLXLMCommon
@testable import MLXAudioSTT

final class Qwen3ASRDecoderTests: XCTestCase {
    func testTextAttention() {
        let config = TextConfig(
            hiddenSize: 32,
            intermediateSize: 128,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            numKeyValueHeads: 2,
            headDim: 8
        )
        let attention = TextAttention(config: config, layerIdx: 0)

        let input = MLXRandom.normal([1, 10, 32])
        let output = attention(input)

        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testTextAttentionWithCache() {
        let config = TextConfig(
            hiddenSize: 32,
            intermediateSize: 128,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            numKeyValueHeads: 2,
            headDim: 8
        )
        let attention = TextAttention(config: config, layerIdx: 0)
        let cache = KVCacheSimple()

        let input = MLXRandom.normal([1, 1, 32])
        let output = attention(input, cache: cache)

        XCTAssertEqual(output.shape, [1, 1, 32])
        XCTAssertEqual(cache.offset, 1)
    }

    func testTextMLP() {
        let config = TextConfig(
            hiddenSize: 32,
            intermediateSize: 128
        )
        let mlp = TextMLP(config: config)

        let input = MLXRandom.normal([1, 10, 32])
        let output = mlp(input)

        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testTextDecoderLayer() {
        let config = TextConfig(
            hiddenSize: 32,
            intermediateSize: 128,
            numAttentionHeads: 4,
            numKeyValueHeads: 2,
            headDim: 8
        )
        let layer = TextDecoderLayer(config: config, layerIdx: 0)

        let input = MLXRandom.normal([1, 10, 32])
        let output = layer(input)

        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testTextModel() {
        let config = TextConfig(
            vocabSize: 1000,
            hiddenSize: 32,
            intermediateSize: 128,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            numKeyValueHeads: 2,
            headDim: 8
        )
        let model = TextModel(config: config)

        let inputIds = MLXArray(0..<10).reshaped([1, 10])
        let output = model(inputIds)

        XCTAssertEqual(output.shape, [1, 10, 32])
    }

    func testForceAlignProcessor() {
        // Test CJK tokenization
        let cjkTokens = ForceAlignProcessor.tokenize("你好世界", language: "zh")
        XCTAssertEqual(cjkTokens.count, 4)

        // Test English tokenization
        let enTokens = ForceAlignProcessor.tokenize("hello world", language: "en")
        XCTAssertEqual(enTokens.count, 2)

        // Test Japanese tokenization
        let jaTokens = ForceAlignProcessor.tokenize("こんにちは", language: "ja")
        XCTAssertGreaterThan(jaTokens.count, 0)
    }

    func testFixTimestampsWithLIS() {
        let items = [
            ForcedAlignItem(word: "a", start: 0.0, end: 0.1),
            ForcedAlignItem(word: "b", start: 0.5, end: 0.6),  // Out of order
            ForcedAlignItem(word: "c", start: 0.2, end: 0.3),
            ForcedAlignItem(word: "d", start: 0.7, end: 0.8)
        ]

        let fixed = fixTimestampsWithLIS(items: items)

        // Check monotonicity
        for i in 1..<fixed.count {
            XCTAssertGreaterThanOrEqual(fixed[i].start, fixed[i - 1].start)
        }
    }
}
