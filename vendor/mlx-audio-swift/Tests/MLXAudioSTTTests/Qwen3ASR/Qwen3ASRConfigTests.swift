//
//  Qwen3ASRConfigTests.swift
//  MLXAudioSTTTests
//
// Tests for Qwen3 ASR configuration parsing.
//

import XCTest
import MLX
@testable import MLXAudioSTT

final class Qwen3ASRConfigTests: XCTestCase {
    func testAudioEncoderConfigCodable() throws {
        let config = AudioEncoderConfig(
            numMelBins: 128,
            encoderLayers: 24,
            encoderAttentionHeads: 16,
            encoderFfnDim: 4096,
            dModel: 1024,
            nWindow: 50,
            outputDim: 2048,
            downsampleHiddenSize: 480
        )

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AudioEncoderConfig.self, from: encoded)

        XCTAssertEqual(decoded.numMelBins, 128)
        XCTAssertEqual(decoded.encoderLayers, 24)
        XCTAssertEqual(decoded.encoderAttentionHeads, 16)
        XCTAssertEqual(decoded.dModel, 1024)
        XCTAssertEqual(decoded.nWindow, 50)
    }

    func testTextConfigCodable() throws {
        let config = TextConfig(
            vocabSize: 151936,
            hiddenSize: 3584,
            intermediateSize: 18944,
            numHiddenLayers: 28,
            numAttentionHeads: 28,
            numKeyValueHeads: 4,
            headDim: 128
        )

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TextConfig.self, from: encoded)

        XCTAssertEqual(decoded.vocabSize, 151936)
        XCTAssertEqual(decoded.numKeyValueHeads, 4)
        XCTAssertEqual(decoded.intermediateSize, 18944)
    }

    func testQwen3ASRModelConfigCodable() throws {
        let audioConfig = AudioEncoderConfig()
        let textConfig = TextConfig()
        let config = Qwen3ASRModelConfig(
            modelType: "qwen3_asr",
            audioConfig: audioConfig,
            textConfig: textConfig,
            audioTokenId: 151676,
            audioStartTokenId: 151669,
            audioEndTokenId: 151670
        )

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Qwen3ASRModelConfig.self, from: encoded)

        XCTAssertEqual(decoded.modelType, "qwen3_asr")
        XCTAssertEqual(decoded.audioTokenId, 151676)
    }

    func testForcedAlignerConfigCodable() throws {
        let config = ForcedAlignerConfig(
            modelType: "qwen3_forced_aligner",
            timestampTokenId: 151671,
            classifyNum: 5000
        )

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ForcedAlignerConfig.self, from: encoded)

        XCTAssertEqual(decoded.modelType, "qwen3_forced_aligner")
        XCTAssertEqual(decoded.timestampTokenId, 151671)
        XCTAssertEqual(decoded.classifyNum, 5000)
    }

    func testThinkerConfigNesting() throws {
        // Test HuggingFace format with thinker_config nesting
        let json = """
        {
            "model_type": "qwen3_asr",
            "thinker_config": {
                "audio_config": {
                    "num_mel_bins": 128,
                    "encoder_layers": 24,
                    "encoder_attention_heads": 16,
                    "d_model": 1024,
                    "encoder_ffn_dim": 4096,
                    "output_dim": 2048,
                    "n_window": 50,
                    "downsample_hidden_size": 480
                },
                "text_config": {
                    "vocab_size": 151936,
                    "hidden_size": 3584,
                    "intermediate_size": 18944,
                    "num_hidden_layers": 28,
                    "num_attention_heads": 28,
                    "num_key_value_heads": 4,
                    "head_dim": 128
                },
                "audio_token_id": 151676,
                "audio_start_token_id": 151669,
                "audio_end_token_id": 151670
            }
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(Qwen3ASRModelConfig.self, from: data)

        XCTAssertEqual(config.audioConfig.numMelBins, 128)
        XCTAssertEqual(config.audioConfig.encoderLayers, 24)
        XCTAssertEqual(config.textConfig.vocabSize, 151936)
        XCTAssertEqual(config.textConfig.numKeyValueHeads, 4)
        XCTAssertEqual(config.audioTokenId, 151676)
    }
}
