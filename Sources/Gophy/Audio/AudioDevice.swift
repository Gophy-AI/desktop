import CoreAudio
import Foundation

struct AudioDevice: Sendable, Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let sampleRate: Double
    let inputChannelCount: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}
