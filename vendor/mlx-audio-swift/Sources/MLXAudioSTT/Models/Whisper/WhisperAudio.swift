//
//  WhisperAudio.swift
//  MLXAudioSTT
//
//  Whisper audio preprocessing matching mlx-audio Python implementation.
//

import Foundation
import MLX
import MLXAudioCore

/// Constants for Whisper audio processing.
public enum WhisperAudioConstants {
    public static let sampleRate = 16000
    public static let nFft = 400
    public static let hopLength = 160
    public static let chunkLength = 30  // seconds
    public static let nSamples = chunkLength * sampleRate  // 480000 samples in a 30-second chunk
    public static let nFrames = nSamples / hopLength  // 3000 frames in a mel spectrogram input
}

/// Pad or trim the audio array to N_SAMPLES (480000), as expected by the encoder.
public func padOrTrim(_ array: MLXArray, length: Int = WhisperAudioConstants.nSamples) -> MLXArray {
    let axis = array.ndim - 1  // Last axis
    let currentLength = array.shape[axis]

    // Trim if too long
    if currentLength > length {
        var slices = [MLXArrayIndex](repeating: 0..., count: array.ndim)
        slices[axis] = 0..<length
        return array[slices]
    }

    // Pad if too short
    if currentLength < length {
        let padAmount = length - currentLength
        let padding = MLXArray.zeros([padAmount])
        return MLX.concatenated([array, padding], axis: axis)
    }

    return array
}

/// Compute the log-Mel spectrogram of audio.
///
/// - Parameters:
///   - audio: Audio waveform in 16 kHz, shape (samples,)
///   - nMels: The number of Mel-frequency filters (80 or 128)
/// - Returns: Log-Mel spectrogram, shape (n_mels, n_frames)
public func logMelSpectrogram(audio: MLXArray, nMels: Int = 80) -> MLXArray {
    // Use MLXAudioCore DSP functions
    let window = MLXAudioCore.hanningWindow(size: WhisperAudioConstants.nFft)
    let freqs = MLXAudioCore.stft(
        audio: audio,
        window: window,
        nFft: WhisperAudioConstants.nFft,
        hopLength: WhisperAudioConstants.hopLength
    )

    // STFT returns [numFrames, nFft/2 + 1], we want to drop the last frequency bin
    let freqsSlice = freqs[0..., 0..<(freqs.shape[1] - 1)]
    let magnitudes = freqsSlice.abs().square()

    // Apply mel filterbank [numFrames, nFreqs] @ [nFreqs, nMels] = [numFrames, nMels]
    let filters = MLXAudioCore.melFilters(
        sampleRate: WhisperAudioConstants.sampleRate,
        nFft: WhisperAudioConstants.nFft,
        nMels: nMels,
        norm: "slaney"
    )

    let melSpec = MLX.matmul(magnitudes, filters)

    // Convert to log scale
    var logSpec = MLX.maximum(melSpec, MLXArray(1e-10)).log10()

    // Two-step normalization:
    // (1) Clamp: log_spec = max(log_spec, log_spec.max() - 8.0)
    let maxVal = logSpec.max()
    logSpec = MLX.maximum(logSpec, maxVal - 8.0)

    // (2) Normalize: log_spec = (log_spec + 4.0) / 4.0
    logSpec = (logSpec + 4.0) / 4.0

    // Transpose to (n_mels, n_frames) for Whisper encoder
    return logSpec.T
}
