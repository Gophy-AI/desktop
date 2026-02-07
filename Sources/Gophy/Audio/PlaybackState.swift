import Foundation

/// Playback state for RecordingPlaybackService
public enum PlaybackState: String, Sendable, Equatable {
    case idle
    case loaded
    case playing
    case paused
    case stopped
}
