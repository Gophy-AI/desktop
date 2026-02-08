//
//  WhisperAudioTests.swift
//  MLXAudioSTTTests
//
//  Tests for Whisper audio preprocessing.
//

import XCTest
import MLX
@testable import MLXAudioSTT

final class WhisperAudioTests: XCTestCase {

    func testPadOrTrimShortAudio() {
        // Create short audio (5 seconds at 16kHz = 80000 samples)
        let shortAudio = MLXArray.full([80000], values: MLXArray(0.5))

        let padded = padOrTrim(shortAudio, length: WhisperAudioConstants.nSamples)

        XCTAssertEqual(padded.shape[0], WhisperAudioConstants.nSamples)

        // Check that original samples are preserved
        XCTAssertEqual(padded[0].item(Float.self), 0.5, accuracy: 1e-6)
        XCTAssertEqual(padded[79999].item(Float.self), 0.5, accuracy: 1e-6)

        // Check that padding is zeros
        XCTAssertEqual(padded[80000].item(Float.self), 0.0, accuracy: 1e-6)
    }

    func testPadOrTrimLongAudio() {
        // Create long audio (60 seconds at 16kHz = 960000 samples)
        let longAudio = MLXArray.full([960000], values: MLXArray(0.5))

        let trimmed = padOrTrim(longAudio, length: WhisperAudioConstants.nSamples)

        XCTAssertEqual(trimmed.shape[0], WhisperAudioConstants.nSamples)

        // Check that first samples are preserved
        XCTAssertEqual(trimmed[0].item(Float.self), 0.5, accuracy: 1e-6)
        XCTAssertEqual(trimmed[WhisperAudioConstants.nSamples - 1].item(Float.self), 0.5, accuracy: 1e-6)
    }

    func testPadOrTrimExactLength() {
        // Create audio of exact length
        let audio = MLXArray.full([WhisperAudioConstants.nSamples], values: MLXArray(0.5))

        let result = padOrTrim(audio, length: WhisperAudioConstants.nSamples)

        XCTAssertEqual(result.shape[0], WhisperAudioConstants.nSamples)
        XCTAssertEqual(result[0].item(Float.self), 0.5, accuracy: 1e-6)
    }

    func testLogMelSpectrogramShape() {
        // Create synthetic audio (sine wave at 440Hz for 30 seconds)
        let sampleRate = WhisperAudioConstants.sampleRate
        let duration = WhisperAudioConstants.chunkLength
        let freq: Float = 440.0

        var samples = [Float](repeating: 0, count: sampleRate * duration)
        for i in 0..<samples.count {
            let t = Float(i) / Float(sampleRate)
            samples[i] = sin(2 * Float.pi * freq * t) * 0.5
        }
        let audio = MLXArray(samples)

        // Compute mel spectrogram with 80 bins
        let melSpec = logMelSpectrogram(audio: audio, nMels: 80)

        // Check shape: (n_mels, n_frames)
        XCTAssertEqual(melSpec.ndim, 2)
        XCTAssertEqual(melSpec.shape[0], 80)
        XCTAssertEqual(melSpec.shape[1], WhisperAudioConstants.nFrames)
    }

    func testLogMelSpectrogramShape128() {
        // Test with 128 mel bins (large model variant)
        let sampleRate = WhisperAudioConstants.sampleRate
        let duration = WhisperAudioConstants.chunkLength

        var samples = [Float](repeating: 0, count: sampleRate * duration)
        for i in 0..<samples.count {
            let t = Float(i) / Float(sampleRate)
            samples[i] = sin(2 * Float.pi * 440 * t) * 0.5
        }
        let audio = MLXArray(samples)

        let melSpec = logMelSpectrogram(audio: audio, nMels: 128)

        XCTAssertEqual(melSpec.ndim, 2)
        XCTAssertEqual(melSpec.shape[0], 128)
        XCTAssertEqual(melSpec.shape[1], WhisperAudioConstants.nFrames)
    }

    func testLogMelSpectrogramNormalization() {
        // Create synthetic audio
        let sampleRate = WhisperAudioConstants.sampleRate
        let duration = WhisperAudioConstants.chunkLength

        var samples = [Float](repeating: 0, count: sampleRate * duration)
        for i in 0..<samples.count {
            let t = Float(i) / Float(sampleRate)
            samples[i] = sin(2 * Float.pi * 440 * t) * 0.5
        }
        let audio = MLXArray(samples)

        let melSpec = logMelSpectrogram(audio: audio, nMels: 80)

        // Verify normalization formula: (log_spec + 4.0) / 4.0
        // After normalization, values should be in a reasonable range
        let minVal = melSpec.min().item(Float.self)
        let maxVal = melSpec.max().item(Float.self)

        // After two-step normalization:
        // (1) Clamp to max - 8
        // (2) (val + 4) / 4
        // So min should be around (max - 8 + 4) / 4 = (max - 4) / 4
        // And max should be (max + 4) / 4

        // Just verify they're in a sensible range (not infinity, not NaN)
        XCTAssertFalse(minVal.isNaN)
        XCTAssertFalse(maxVal.isNaN)
        XCTAssertFalse(minVal.isInfinite)
        XCTAssertFalse(maxVal.isInfinite)

        // Normalized values should typically be in range [0, 2]
        XCTAssertGreaterThanOrEqual(minVal, -1.0)
        XCTAssertLessThanOrEqual(maxVal, 3.0)
    }

    func testLogMelSpectrogramSilence() {
        // Test with silence (zeros)
        let audio = MLXArray.zeros([WhisperAudioConstants.nSamples])

        let melSpec = logMelSpectrogram(audio: audio, nMels: 80)

        XCTAssertEqual(melSpec.shape[0], 80)
        XCTAssertEqual(melSpec.shape[1], WhisperAudioConstants.nFrames)

        // Silence should produce low values after log scaling
        let maxVal = melSpec.max().item(Float.self)
        XCTAssertLessThan(maxVal, 2.0)
    }
}
