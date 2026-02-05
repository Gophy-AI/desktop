import XCTest
import CoreAudio
@testable import Gophy

final class AudioDeviceManagerTests: XCTestCase {
    var manager: AudioDeviceManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = AudioDeviceManager()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    func testManagerCanBeInitialized() {
        XCTAssertNotNil(manager)
    }

    func testListInputDevicesReturnsAtLeastOneDeviceIfHardwareAvailable() throws {
        let devices = try manager.listInputDevices()

        let hasAudioHardware = checkForAudioHardware()
        if hasAudioHardware {
            XCTAssertFalse(devices.isEmpty, "Expected at least one input device when hardware is available")
        } else {
            XCTAssertTrue(devices.isEmpty, "Expected no devices in CI environment without audio hardware")
        }
    }

    func testDeviceNamesAreNonEmpty() throws {
        let devices = try manager.listInputDevices()

        for device in devices {
            XCTAssertFalse(device.name.isEmpty, "Device name should not be empty")
            XCTAssertFalse(device.uid.isEmpty, "Device UID should not be empty")
        }
    }

    func testDevicesHaveValidSampleRate() throws {
        let devices = try manager.listInputDevices()

        for device in devices {
            XCTAssertGreaterThan(device.sampleRate, 0.0, "Sample rate should be positive")
            XCTAssertLessThanOrEqual(device.sampleRate, 192000.0, "Sample rate should be reasonable")
        }
    }

    func testDevicesHaveValidInputChannelCount() throws {
        let devices = try manager.listInputDevices()

        for device in devices {
            XCTAssertGreaterThanOrEqual(device.inputChannelCount, 0, "Input channel count should be non-negative")
            XCTAssertLessThanOrEqual(device.inputChannelCount, 32, "Input channel count should be reasonable")
        }
    }

    func testSelectedDeviceIsNilInitially() {
        XCTAssertNil(manager.selectedDevice)
    }

    func testSelectDeviceSetsSelectedDevice() throws {
        let devices = try manager.listInputDevices()

        guard let firstDevice = devices.first else {
            throw XCTSkip("No audio devices available for testing")
        }

        manager.selectDevice(firstDevice)
        XCTAssertEqual(manager.selectedDevice, firstDevice)
    }

    func testDeviceChangeStreamDeliversInitialValue() async throws {
        var receivedDevices: [AudioDevice?] = []

        let expectation = XCTestExpectation(description: "Receive initial device list notification")

        Task {
            var count = 0
            for await devices in manager.deviceChangeStream {
                receivedDevices.append(devices.first)
                count += 1
                if count == 1 {
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedDevices.count, 1)
    }

    func testDeviceChangeStreamDeliversUpdateWhenDeviceChanges() async throws {
        guard checkForAudioHardware() else {
            throw XCTSkip("No audio hardware available for device change testing")
        }

        var receivedNotifications = 0
        let expectation = XCTestExpectation(description: "Receive device change notification")

        Task {
            for await _ in manager.deviceChangeStream {
                receivedNotifications += 1
                if receivedNotifications == 2 {
                    expectation.fulfill()
                    break
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        manager.triggerDeviceListRefresh()

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertGreaterThanOrEqual(receivedNotifications, 2)
    }

    private func checkForAudioHardware() -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }
}
