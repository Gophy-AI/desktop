import Foundation
import Observation
import AppKit

@MainActor
@Observable
public final class SettingsViewModel {
    private let audioDeviceManager: AudioDeviceManager
    private let storageManager: StorageManager
    private let registry: ModelRegistry

    var availableInputDevices: [AudioDevice] = []
    var selectedDevice: AudioDevice?
    var systemAudioEnabled: Bool = false
    var vadSensitivity: Double = 0.5
    var autoSuggestInterval: Double = 30.0

    var databaseLocation: String
    var totalStorageGB: Double = 0.0
    var totalModelStorageGB: Double = 0.0

    var showClearDataConfirmation: Bool = false
    var errorMessage: String?

    private var deviceListenerTask: Task<Void, Never>?

    init(
        audioDeviceManager: AudioDeviceManager,
        storageManager: StorageManager,
        registry: ModelRegistry
    ) {
        self.audioDeviceManager = audioDeviceManager
        self.storageManager = storageManager
        self.registry = registry
        self.databaseLocation = storageManager.databaseDirectory.path

        loadSettings()
        startDeviceListener()
        calculateStorage()
    }


    private func loadSettings() {
        let defaults = UserDefaults.standard

        if let savedDeviceUID = defaults.string(forKey: "selectedAudioDeviceUID") {
            do {
                let devices = try audioDeviceManager.listInputDevices()
                selectedDevice = devices.first { $0.uid == savedDeviceUID }
            } catch {
                print("Error loading audio devices: \(error)")
            }
        }

        systemAudioEnabled = defaults.bool(forKey: "systemAudioEnabled")
        vadSensitivity = defaults.double(forKey: "vadSensitivity")
        if vadSensitivity == 0 {
            vadSensitivity = 0.5
        }

        autoSuggestInterval = defaults.double(forKey: "autoSuggestInterval")
        if autoSuggestInterval == 0 {
            autoSuggestInterval = 30.0
        }
    }

    private func startDeviceListener() {
        deviceListenerTask = Task {
            for await devices in audioDeviceManager.deviceChangeStream {
                self.availableInputDevices = devices

                if selectedDevice == nil && !devices.isEmpty {
                    selectedDevice = devices.first
                }
            }
        }

        do {
            availableInputDevices = try audioDeviceManager.listInputDevices()
            if selectedDevice == nil && !availableInputDevices.isEmpty {
                selectedDevice = availableInputDevices.first
            }
        } catch {
            print("Error listing initial devices: \(error)")
        }
    }

    func selectInputDevice(_ device: AudioDevice) {
        selectedDevice = device
        audioDeviceManager.selectDevice(device)

        let defaults = UserDefaults.standard
        defaults.set(device.uid, forKey: "selectedAudioDeviceUID")
    }

    func toggleSystemAudio() {
        systemAudioEnabled.toggle()
        let defaults = UserDefaults.standard
        defaults.set(systemAudioEnabled, forKey: "systemAudioEnabled")
    }

    func updateVADSensitivity(_ value: Double) {
        vadSensitivity = value
        let defaults = UserDefaults.standard
        defaults.set(vadSensitivity, forKey: "vadSensitivity")
    }

    func updateAutoSuggestInterval(_ value: Double) {
        autoSuggestInterval = value
        let defaults = UserDefaults.standard
        defaults.set(autoSuggestInterval, forKey: "autoSuggestInterval")
    }

    func openDatabaseInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storageManager.databaseDirectory.path)
    }

    func calculateStorage() {
        let fileManager = FileManager.default

        var totalSize: Int64 = 0
        if let enumerator = fileManager.enumerator(
            at: storageManager.databaseDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        totalStorageGB = Double(totalSize) / 1_000_000_000

        var modelSize: Int64 = 0
        if let enumerator = fileManager.enumerator(
            at: storageManager.modelsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    modelSize += Int64(fileSize)
                }
            }
        }
        totalModelStorageGB = Double(modelSize) / 1_000_000_000
    }

    func confirmClearData() {
        showClearDataConfirmation = true
    }

    func clearAllData() async {
        do {
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: storageManager.databaseDirectory.path) {
                try fileManager.removeItem(at: storageManager.databaseDirectory)
            }

            try fileManager.createDirectory(
                at: storageManager.databaseDirectory,
                withIntermediateDirectories: true
            )

            calculateStorage()
            errorMessage = nil
            showClearDataConfirmation = false
        } catch {
            errorMessage = "Failed to clear data: \(error.localizedDescription)"
            showClearDataConfirmation = false
        }
    }
}
