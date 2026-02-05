import CoreAudio
import Foundation

struct AudioDevice: Sendable, Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let sampleRate: Double
    let inputChannelCount: Int
}
