//
//  ParakeetAudio.swift
//  MLXAudioSTT
//
//  Parakeet-specific audio preprocessing (preemphasis + per-feature normalization).
//

import Foundation
import MLX
import MLXAudioCore

// MARK: - Preprocess Configuration

/// Audio preprocessing configuration for Parakeet models.
public struct PreprocessArgs: Codable, Sendable {
    public var sampleRate: Int
    public var windowSize: Double
    public var windowStride: Double
    public var window: String
    public var features: Int
    public var nFft: Int
    public var preemph: Double
    public var normalize: String

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case windowSize = "window_size"
        case windowStride = "window_stride"
        case window
        case features
        case nFft = "n_fft"
        case preemph
        case normalize
    }

    public init(
        sampleRate: Int = 16000,
        windowSize: Double = 0.025,
        windowStride: Double = 0.01,
        window: String = "hann",
        features: Int = 80,
        nFft: Int = 512,
        preemph: Double = 0.97,
        normalize: String = "per_feature"
    ) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.windowStride = windowStride
        self.window = window
        self.features = features
        self.nFft = nFft
        self.preemph = preemph
        self.normalize = normalize
    }
}

// MARK: - Audio Preprocessing Functions

/// Apply preemphasis filter to audio signal.
///
/// Preemphasis filter: output[i] = input[i+1] - coeff * input[i]
///
/// - Parameters:
///   - audio: Input audio waveform [samples]
///   - coeff: Preemphasis coefficient (default 0.97)
/// - Returns: Preemphasized audio [samples-1]
public func preemphasis(audio: MLXArray, coeff: Float = 0.97) -> MLXArray {
    guard audio.ndim == 1 else {
        fatalError("Audio must be 1D array")
    }

    let nSamples = audio.shape[0]
    guard nSamples > 1 else {
        return audio
    }

    // output[i] = input[i+1] - coeff * input[i]
    let current = audio[0..<(nSamples - 1)]
    let next = audio[1..<nSamples]

    return next - (coeff * current)
}

/// Compute log-mel spectrogram with preemphasis and per-feature normalization.
///
/// Steps:
/// 1. Apply preemphasis filter
/// 2. Compute STFT with Hann window
/// 3. Apply mel filterbank
/// 4. Log transformation: log(mel + 1e-20)
/// 5. Per-feature normalization (zero-mean, unit-variance per mel bin)
///
/// - Parameters:
///   - audio: Input audio waveform [samples]
///   - args: Preprocessing arguments
/// - Returns: Log-mel spectrogram [features, time]
public func logMelSpectrogram(audio: MLXArray, args: PreprocessArgs = PreprocessArgs()) -> MLXArray {
    // 1. Apply preemphasis
    let preemphasizedAudio = preemphasis(audio: audio, coeff: Float(args.preemph))

    // 2. Compute STFT parameters
    let hopLength = Int(Double(args.sampleRate) * args.windowStride)
    let windowLength = Int(Double(args.sampleRate) * args.windowSize)

    // 3. Compute STFT
    let window = MLXAudioCore.hanningWindow(size: windowLength)
    let stftResult = MLXAudioCore.stft(
        audio: preemphasizedAudio,
        window: window,
        nFft: args.nFft,
        hopLength: hopLength
    )

    // 4. Compute power spectrum: |STFT|^2
    let magnitude = MLX.abs(stftResult)
    let powerSpectrum = magnitude * magnitude

    // 5. Apply mel filterbank
    let melFilters = MLXAudioCore.melFilters(
        sampleRate: args.sampleRate,
        nFft: args.nFft,
        nMels: args.features
    )

    // melFilters shape: [nMels, nFft/2 + 1]
    // powerSpectrum shape: [nFft/2 + 1, time]
    // Result shape: [nMels, time]
    let melSpectrum = matmul(melFilters, powerSpectrum)

    // 6. Log transformation
    let logMel = log(melSpectrum + 1e-20)

    // 7. Per-feature normalization (zero-mean, unit-variance per mel bin)
    if args.normalize == "per_feature" {
        return perFeatureNormalize(logMel)
    } else {
        return logMel
    }
}

/// Normalize mel spectrogram per feature (zero-mean, unit-variance per mel bin).
///
/// - Parameter melSpec: Mel spectrogram [features, time]
/// - Returns: Normalized mel spectrogram [features, time]
private func perFeatureNormalize(_ melSpec: MLXArray) -> MLXArray {
    // Compute mean and std per mel bin (axis=1 for time dimension)
    let mean = melSpec.mean(axis: 1, keepDims: true)
    let variance = ((melSpec - mean) * (melSpec - mean)).mean(axis: 1, keepDims: true)
    let std = sqrt(variance + 1e-10)

    return (melSpec - mean) / std
}
