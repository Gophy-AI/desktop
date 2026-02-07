import AVFoundation
import Foundation
import os.log

private let importLogger = Logger(subsystem: "com.gophy.app", category: "AudioFileImporter")

/// Metadata about an imported audio file
public struct AudioFileInfo: Sendable, Equatable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int
    public let format: String

    public init(fileURL: URL, duration: TimeInterval, sampleRate: Double, channelCount: Int, format: String) {
        self.fileURL = fileURL
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.format = format
    }
}

/// Errors that can occur during audio file import
public enum AudioFileImportError: Error, LocalizedError, Sendable {
    case fileNotFound(URL)
    case unsupportedFormat(String)
    case unableToReadFile(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Audio file not found: \(url.path)"
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: \(ext)"
        case .unableToReadFile(let reason):
            return "Unable to read audio file: \(reason)"
        }
    }
}

/// Validates and reads metadata from audio files without loading full audio into memory
public struct AudioFileImporter: Sendable {

    /// Formats natively supported by AVFoundation on macOS
    public static let supportedFormats: [String] = ["mp3", "wav", "m4a", "mp4", "aiff", "caf", "flac"]

    public init() {}

    /// Validate and read metadata from an audio file
    /// - Parameter url: File URL of the audio file
    /// - Returns: AudioFileInfo with duration, sample rate, channel count, and format
    /// - Throws: AudioFileImportError if file is missing, unsupported, or unreadable
    public func importFile(url: URL) async throws -> AudioFileInfo {
        let fileExtension = url.pathExtension.lowercased()

        guard Self.supportedFormats.contains(fileExtension) else {
            importLogger.error("Unsupported format: \(fileExtension, privacy: .public)")
            throw AudioFileImportError.unsupportedFormat(fileExtension)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            importLogger.error("File not found: \(url.path, privacy: .public)")
            throw AudioFileImportError.fileNotFound(url)
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let processingFormat = audioFile.processingFormat
            let frameCount = audioFile.length
            let sampleRate = processingFormat.sampleRate
            let channelCount = Int(processingFormat.channelCount)
            let duration = Double(frameCount) / sampleRate

            importLogger.info("Imported \(fileExtension, privacy: .public): \(String(format: "%.1f", duration), privacy: .public)s, \(sampleRate, privacy: .public)Hz, \(channelCount, privacy: .public)ch")

            return AudioFileInfo(
                fileURL: url,
                duration: duration,
                sampleRate: sampleRate,
                channelCount: channelCount,
                format: fileExtension
            )
        } catch {
            importLogger.error("Failed to read audio file: \(error.localizedDescription, privacy: .public)")
            throw AudioFileImportError.unableToReadFile(error.localizedDescription)
        }
    }
}
