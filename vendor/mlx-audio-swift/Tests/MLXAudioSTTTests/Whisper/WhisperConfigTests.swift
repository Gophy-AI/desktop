//
//  WhisperConfigTests.swift
//  MLXAudioSTTTests
//
//  Tests for Whisper configuration parsing and serialization.
//

import XCTest
import MLX
@testable import MLXAudioSTT

final class WhisperConfigTests: XCTestCase {

    func testModelDimensionsCodableRoundTrip() throws {
        let original = ModelDimensions(
            nMels: 80,
            nAudioCtx: 1500,
            nAudioState: 384,
            nAudioHead: 6,
            nAudioLayer: 4,
            nVocab: 51864,
            nTextCtx: 448,
            nTextState: 384,
            nTextHead: 6,
            nTextLayer: 4
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ModelDimensions.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testModelDimensionsFromMLXFormat() throws {
        let json = """
        {
            "n_mels": 80,
            "n_audio_ctx": 1500,
            "n_audio_state": 384,
            "n_audio_head": 6,
            "n_audio_layer": 4,
            "n_vocab": 51864,
            "n_text_ctx": 448,
            "n_text_state": 384,
            "n_text_head": 6,
            "n_text_layer": 4
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dims = try decoder.decode(ModelDimensions.self, from: data)

        XCTAssertEqual(dims.nMels, 80)
        XCTAssertEqual(dims.nAudioCtx, 1500)
        XCTAssertEqual(dims.nAudioState, 384)
        XCTAssertEqual(dims.nAudioHead, 6)
        XCTAssertEqual(dims.nAudioLayer, 4)
        XCTAssertEqual(dims.nVocab, 51864)
        XCTAssertEqual(dims.nTextCtx, 448)
        XCTAssertEqual(dims.nTextState, 384)
        XCTAssertEqual(dims.nTextHead, 6)
        XCTAssertEqual(dims.nTextLayer, 4)
    }

    func testModelDimensionsFromHuggingFaceFormat() throws {
        let json = """
        {
            "num_mel_bins": 128,
            "max_source_positions": 1500,
            "d_model": 1280,
            "encoder_attention_heads": 20,
            "encoder_layers": 32,
            "vocab_size": 51866,
            "max_target_positions": 448,
            "decoder_attention_heads": 20,
            "decoder_layers": 32
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dims = try decoder.decode(ModelDimensions.self, from: data)

        XCTAssertEqual(dims.nMels, 128)
        XCTAssertEqual(dims.nAudioCtx, 1500)
        XCTAssertEqual(dims.nAudioState, 1280)
        XCTAssertEqual(dims.nAudioHead, 20)
        XCTAssertEqual(dims.nAudioLayer, 32)
        XCTAssertEqual(dims.nVocab, 51866)
        XCTAssertEqual(dims.nTextCtx, 448)
        XCTAssertEqual(dims.nTextState, 1280)
        XCTAssertEqual(dims.nTextHead, 20)
        XCTAssertEqual(dims.nTextLayer, 32)
    }

    func testModelDimensionsDefaults() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dims = try decoder.decode(ModelDimensions.self, from: data)

        // Verify defaults match Whisper tiny model
        XCTAssertEqual(dims.nMels, 80)
        XCTAssertEqual(dims.nAudioCtx, 1500)
        XCTAssertEqual(dims.nAudioState, 384)
        XCTAssertEqual(dims.nAudioHead, 6)
        XCTAssertEqual(dims.nAudioLayer, 4)
    }

    func testWhisperModelConfigDecoding() throws {
        let json = """
        {
            "model_type": "whisper",
            "n_mels": 80,
            "n_audio_ctx": 1500,
            "n_audio_state": 512,
            "n_audio_head": 8,
            "n_audio_layer": 6,
            "n_vocab": 51864,
            "n_text_ctx": 448,
            "n_text_state": 512,
            "n_text_head": 8,
            "n_text_layer": 6
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(WhisperModelConfig.self, from: data)

        XCTAssertEqual(config.modelType, "whisper")
        XCTAssertEqual(config.dimensions.nMels, 80)
        XCTAssertEqual(config.dimensions.nAudioState, 512)
        XCTAssertEqual(config.dimensions.nAudioHead, 8)
        XCTAssertEqual(config.dimensions.nAudioLayer, 6)
    }

    func testLargeModelVariant() throws {
        let json = """
        {
            "num_mel_bins": 128,
            "d_model": 1280,
            "encoder_attention_heads": 20,
            "encoder_layers": 32,
            "decoder_attention_heads": 20,
            "decoder_layers": 32
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let dims = try decoder.decode(ModelDimensions.self, from: data)

        // Large model variant uses 128 mel bins
        XCTAssertEqual(dims.nMels, 128)
        XCTAssertEqual(dims.nAudioState, 1280)
        XCTAssertEqual(dims.nAudioHead, 20)
        XCTAssertEqual(dims.nAudioLayer, 32)
    }
}
