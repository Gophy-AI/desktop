import CoreAudio
import AudioToolbox
import Foundation

final class AudioDeviceManager: Sendable {
    private final class Box: @unchecked Sendable {
        var value: AudioDevice?
        let lock = NSLock()

        init(_ value: AudioDevice? = nil) {
            self.value = value
        }

        func get() -> AudioDevice? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: AudioDevice?) {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    private let _selectedDevice: Box
    private let deviceChangeContinuation: AsyncStream<[AudioDevice]>.Continuation

    let deviceChangeStream: AsyncStream<[AudioDevice]>

    var selectedDevice: AudioDevice? {
        _selectedDevice.get()
    }

    init() {
        self._selectedDevice = Box()

        var continuation: AsyncStream<[AudioDevice]>.Continuation!
        self.deviceChangeStream = AsyncStream { cont in
            continuation = cont
        }
        self.deviceChangeContinuation = continuation

        self.setupDeviceChangeListener()
        self.notifyDeviceChange()
    }

    deinit {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            deviceChangeListenerProc,
            Unmanaged.passUnretained(self).toOpaque()
        )

        deviceChangeContinuation.finish()
    }

    func listInputDevices() throws -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            return []
        }

        let devices = deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard hasInputChannels(deviceID: deviceID) else {
                return nil
            }

            guard let name = getDeviceName(deviceID: deviceID),
                  let uid = getDeviceUID(deviceID: deviceID),
                  let sampleRate = getDeviceSampleRate(deviceID: deviceID) else {
                return nil
            }

            let inputChannelCount = getInputChannelCount(deviceID: deviceID)

            return AudioDevice(
                id: deviceID,
                name: name,
                uid: uid,
                sampleRate: sampleRate,
                inputChannelCount: inputChannelCount
            )
        }

        return devices
    }

    func selectDevice(_ device: AudioDevice) {
        _selectedDevice.set(device)
    }

    func triggerDeviceListRefresh() {
        notifyDeviceChange()
    }

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            deviceChangeListenerProc,
            selfPtr
        )
    }

    fileprivate func notifyDeviceChange() {
        do {
            let devices = try listInputDevices()
            deviceChangeContinuation.yield(devices)
        } catch {
            deviceChangeContinuation.yield([])
        }
    }

    private func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr, dataSize > 0 else {
            return false
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferList
        )

        guard getStatus == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let totalChannels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }

        return totalChannels > 0
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var nameRef: Unmanaged<CFString>?

        let status = withUnsafeMutablePointer(to: &nameRef) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                ptr
            )
        }

        guard status == noErr, let cfString = nameRef?.takeUnretainedValue() else {
            return nil
        }

        return cfString as String
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var uidRef: Unmanaged<CFString>?

        let status = withUnsafeMutablePointer(to: &uidRef) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                ptr
            )
        }

        guard status == noErr, let cfString = uidRef?.takeUnretainedValue() else {
            return nil
        }

        return cfString as String
    }

    private func getDeviceSampleRate(deviceID: AudioDeviceID) -> Double? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<Float64>.size)
        var sampleRate: Float64 = 0.0

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &sampleRate
        )

        guard status == noErr else {
            return nil
        }

        return sampleRate
    }

    private func getInputChannelCount(deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr, dataSize > 0 else {
            return 0
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferList
        )

        guard getStatus == noErr else {
            return 0
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

private func deviceChangeListenerProc(
    _: AudioObjectID,
    _: UInt32,
    _: UnsafePointer<AudioObjectPropertyAddress>,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = clientData else {
        return noErr
    }

    let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData).takeUnretainedValue()
    manager.notifyDeviceChange()

    return noErr
}
