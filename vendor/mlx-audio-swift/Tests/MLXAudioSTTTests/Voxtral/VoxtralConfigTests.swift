//
//  VoxtralConfigTests.swift
//  MLXAudioSTTTests
//
// Tests for Voxtral configuration parsing

import XCTest
@testable import MLXAudioSTT

final class VoxtralConfigTests: XCTestCase {

    func testAudioConfigDefaults() throws {
        let config = VoxtralAudioConfig()

        XCTAssertEqual(config.numMelBins, 128)
        XCTAssertEqual(config.hiddenSize, 1280)
        XCTAssertEqual(config.numHiddenLayers, 32)
        XCTAssertEqual(config.intermediateSize, 5120)
        XCTAssertEqual(config.numAttentionHeads, 20)
        XCTAssertEqual(config.numKeyValueHeads, 20)
        XCTAssertEqual(config.headDim, 64)
        XCTAssertEqual(config.ropeTheta, 1000000.0)
        XCTAssertEqual(config.encoderLayers, 32)
        XCTAssertEqual(config.encoderAttentionHeads, 20)
        XCTAssertEqual(config.dModel, 1280)
        XCTAssertEqual(config.maxSourcePositions, 1500)
    }

    func testAudioConfigCodable() throws {
        let original = VoxtralAudioConfig(
            hiddenSize: 1280,
            numHiddenLayers: 32,
            intermediateSize: 5120,
            numAttentionHeads: 20,
            numKeyValueHeads: 20,
            rmsNormEps: 1e-5,
            headDim: 64,
            ropeTheta: 1000000.0,
            vocabSize: 51866,
            numMelBins: 128,
            encoderLayers: 32,
            encoderAttentionHeads: 20,
            encoderFfnDim: 5120,
            encoderLayerdrop: 0.0,
            dModel: 1280,
            dropout: 0.0,
            attentionDropout: 0.0,
            activationFunction: "gelu",
            activationDropout: 0.0,
            scaleEmbedding: false,
            initializerRange: 0.02,
            maxSourcePositions: 1500
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VoxtralAudioConfig.self, from: data)

        XCTAssertEqual(decoded.numMelBins, original.numMelBins)
        XCTAssertEqual(decoded.hiddenSize, original.hiddenSize)
        XCTAssertEqual(decoded.intermediateSize, original.intermediateSize)
        XCTAssertEqual(decoded.numAttentionHeads, original.numAttentionHeads)
        XCTAssertEqual(decoded.headDim, original.headDim)
        XCTAssertEqual(decoded.ropeTheta, original.ropeTheta)
        XCTAssertEqual(decoded.maxSourcePositions, original.maxSourcePositions)
    }

    func testTextConfigDefaults() throws {
        let config = VoxtralTextConfig()

        XCTAssertEqual(config.modelType, "llama")
        XCTAssertEqual(config.vocabSize, 131072)
        XCTAssertEqual(config.hiddenSize, 3072)
        XCTAssertEqual(config.numHiddenLayers, 30)
        XCTAssertEqual(config.numAttentionHeads, 32)
        XCTAssertEqual(config.numKeyValueHeads, 8)
        XCTAssertEqual(config.headDim, 128)
        XCTAssertEqual(config.ropeTheta, 100000000.0)
        XCTAssertEqual(config.layerTypes.count, 30)
        XCTAssertEqual(config.layerTypes.first, "full_attention")
    }

    func testTextConfigCodable() throws {
        let original = VoxtralTextConfig(
            modelType: "llama",
            vocabSize: 131072,
            maxPositionEmbeddings: 131072,
            hiddenSize: 3072,
            intermediateSize: 8192,
            numHiddenLayers: 30,
            numAttentionHeads: 32,
            numKeyValueHeads: 8,
            hiddenAct: "silu",
            initializerRange: 0.02,
            rmsNormEps: 1e-5,
            useCache: true,
            ropeScaling: nil,
            attentionBias: false,
            attentionDropout: 0.0,
            mlpBias: false,
            headDim: 128,
            tieWordEmbeddings: false,
            bosTokenId: 1,
            eosTokenId: 2,
            slidingWindow: nil,
            ropeTraditional: false,
            ropeTheta: 100000000.0,
            layerTypes: Array(repeating: "full_attention", count: 30)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VoxtralTextConfig.self, from: data)

        XCTAssertEqual(decoded.vocabSize, original.vocabSize)
        XCTAssertEqual(decoded.hiddenSize, original.hiddenSize)
        XCTAssertEqual(decoded.numHiddenLayers, original.numHiddenLayers)
        XCTAssertEqual(decoded.numAttentionHeads, original.numAttentionHeads)
        XCTAssertEqual(decoded.numKeyValueHeads, original.numKeyValueHeads)
        XCTAssertEqual(decoded.headDim, original.headDim)
        XCTAssertEqual(decoded.ropeTheta, original.ropeTheta)
        XCTAssertEqual(decoded.layerTypes.count, original.layerTypes.count)
    }

    func testModelConfigDefaults() throws {
        let config = VoxtralModelConfig()

        XCTAssertEqual(config.modelType, "voxtral")
        XCTAssertEqual(config.audioTokenId, 24)
        XCTAssertEqual(config.projectorHiddenAct, "gelu")
        XCTAssertEqual(config.vocabSize, config.textConfig.vocabSize)
        XCTAssertEqual(config.hiddenSize, config.textConfig.hiddenSize)
    }

    func testModelConfigCodable() throws {
        let audioConfig = VoxtralAudioConfig()
        let textConfig = VoxtralTextConfig()
        let original = VoxtralModelConfig(
            audioConfig: audioConfig,
            textConfig: textConfig,
            modelRepo: "test/voxtral-model",
            modelType: "voxtral",
            audioTokenId: 24,
            projectorHiddenAct: "gelu",
            vocabSize: 131072,
            hiddenSize: 3072
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VoxtralModelConfig.self, from: data)

        XCTAssertEqual(decoded.modelType, original.modelType)
        XCTAssertEqual(decoded.audioTokenId, 24)
        XCTAssertEqual(decoded.projectorHiddenAct, "gelu")
        XCTAssertEqual(decoded.vocabSize, original.vocabSize)
        XCTAssertEqual(decoded.hiddenSize, original.hiddenSize)
    }

    func testModelConfigFromJSON() throws {
        let json = """
        {
            "model_type": "voxtral",
            "audio_token_id": 24,
            "projector_hidden_act": "gelu",
            "vocab_size": 131072,
            "hidden_size": 3072,
            "audio_config": {
                "num_mel_bins": 128,
                "hidden_size": 1280,
                "num_hidden_layers": 32,
                "intermediate_size": 5120,
                "num_attention_heads": 20,
                "num_key_value_heads": 20,
                "head_dim": 64,
                "rope_theta": 1000000.0,
                "encoder_layers": 32,
                "encoder_attention_heads": 20,
                "d_model": 1280,
                "max_source_positions": 1500
            },
            "text_config": {
                "model_type": "llama",
                "vocab_size": 131072,
                "hidden_size": 3072,
                "num_hidden_layers": 30,
                "num_attention_heads": 32,
                "num_key_value_heads": 8,
                "head_dim": 128,
                "rope_theta": 100000000.0
            }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(VoxtralModelConfig.self, from: data)

        XCTAssertEqual(config.modelType, "voxtral")
        XCTAssertEqual(config.audioTokenId, 24)
        XCTAssertEqual(config.audioConfig.numMelBins, 128)
        XCTAssertEqual(config.audioConfig.hiddenSize, 1280)
        XCTAssertEqual(config.textConfig.vocabSize, 131072)
        XCTAssertEqual(config.textConfig.hiddenSize, 3072)
    }
}
