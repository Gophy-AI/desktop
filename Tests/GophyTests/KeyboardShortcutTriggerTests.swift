import Testing
import Foundation
@testable import Gophy

// MARK: - KeyboardShortcutTrigger Tests

@Suite("KeyboardShortcutTrigger")
struct KeyboardShortcutTriggerTests {

    @Test("default shortcuts are registered")
    func defaultShortcutsRegistered() async throws {
        let trigger = KeyboardShortcutTrigger()
        let shortcuts = await trigger.registeredShortcuts

        #expect(shortcuts.count == 4)

        let toolNames = shortcuts.map(\.toolName)
        #expect(toolNames.contains("remember"))
        #expect(toolNames.contains("take_note"))
        #expect(toolNames.contains("generate_summary"))
        #expect(toolNames.contains("search_knowledge"))
    }

    @Test("shortcuts only active during meeting (isActive flag)")
    func shortcutsOnlyActiveDuringMeeting() async throws {
        let trigger = KeyboardShortcutTrigger()

        let isActive = await trigger.isActive
        #expect(!isActive)

        await trigger.activate(meetingId: "meeting-1")
        let activeAfter = await trigger.isActive
        #expect(activeAfter)

        await trigger.deactivate()
        let activeAfterDeactivate = await trigger.isActive
        #expect(!activeAfterDeactivate)
    }

    @Test("shortcuts disabled when no meeting is active")
    func shortcutsDisabledWithoutMeeting() async throws {
        let trigger = KeyboardShortcutTrigger()

        // Simulate a key press event when inactive
        let handled = await trigger.handleKeyEvent(keyEquivalent: "r", modifiers: [.command, .shift])
        #expect(!handled)
    }

    @Test("custom shortcut bindings can be registered")
    func customShortcutRegistration() async throws {
        let trigger = KeyboardShortcutTrigger()

        let custom = AutomationShortcut(
            keyEquivalent: "h",
            modifiers: [.command, .shift],
            toolName: "custom_help",
            buildArgs: { meetingId in ["meetingId": meetingId] },
            description: "Custom help shortcut"
        )
        await trigger.registerShortcut(custom)

        let shortcuts = await trigger.registeredShortcuts
        let toolNames = shortcuts.map(\.toolName)
        #expect(toolNames.contains("custom_help"))
    }

    @Test("Cmd+Shift+R triggers remember when active")
    func cmdShiftRTriggersRemember() async throws {
        let trigger = KeyboardShortcutTrigger()
        await trigger.activate(meetingId: "meeting-1")

        let handled = await trigger.handleKeyEvent(keyEquivalent: "r", modifiers: [.command, .shift])
        #expect(handled)

        let events = await trigger.pendingEvents
        let toolNames = events.compactMap { event -> String? in
            if case .triggered(let name, _) = event { return name }
            return nil
        }
        #expect(toolNames.contains("remember"))
    }

    @Test("Cmd+Shift+N triggers take_note when active")
    func cmdShiftNTriggersNote() async throws {
        let trigger = KeyboardShortcutTrigger()
        await trigger.activate(meetingId: "meeting-1")

        let handled = await trigger.handleKeyEvent(keyEquivalent: "n", modifiers: [.command, .shift])
        #expect(handled)

        let events = await trigger.pendingEvents
        let toolNames = events.compactMap { event -> String? in
            if case .triggered(let name, _) = event { return name }
            return nil
        }
        #expect(toolNames.contains("take_note"))
    }

    @Test("Cmd+Shift+S triggers generate_summary when active")
    func cmdShiftSTriggersSummary() async throws {
        let trigger = KeyboardShortcutTrigger()
        await trigger.activate(meetingId: "meeting-1")

        let handled = await trigger.handleKeyEvent(keyEquivalent: "s", modifiers: [.command, .shift])
        #expect(handled)

        let events = await trigger.pendingEvents
        let toolNames = events.compactMap { event -> String? in
            if case .triggered(let name, _) = event { return name }
            return nil
        }
        #expect(toolNames.contains("generate_summary"))
    }

    @Test("Cmd+Shift+F triggers search_knowledge when active")
    func cmdShiftFTriggersSearch() async throws {
        let trigger = KeyboardShortcutTrigger()
        await trigger.activate(meetingId: "meeting-1")

        let handled = await trigger.handleKeyEvent(keyEquivalent: "f", modifiers: [.command, .shift])
        #expect(handled)

        let events = await trigger.pendingEvents
        let toolNames = events.compactMap { event -> String? in
            if case .triggered(let name, _) = event { return name }
            return nil
        }
        #expect(toolNames.contains("search_knowledge"))
    }

    @Test("deactivate stops triggering")
    func deactivateStopsTriggering() async throws {
        let trigger = KeyboardShortcutTrigger()
        await trigger.activate(meetingId: "meeting-1")
        await trigger.deactivate()

        let handled = await trigger.handleKeyEvent(keyEquivalent: "r", modifiers: [.command, .shift])
        #expect(!handled)
    }

    @Test("trigger source is keyboardShortcut")
    func triggerSourceIsKeyboard() async throws {
        let trigger = KeyboardShortcutTrigger()
        await trigger.activate(meetingId: "meeting-1")

        _ = await trigger.handleKeyEvent(keyEquivalent: "r", modifiers: [.command, .shift])

        let events = await trigger.pendingEvents
        let sources = events.compactMap { event -> TriggerSource? in
            if case .triggered(_, let source) = event { return source }
            return nil
        }
        #expect(sources.allSatisfy { $0 == .keyboardShortcut })
    }
}
