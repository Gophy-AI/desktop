import Testing
import Foundation
@testable import Gophy

// MARK: - AutomationManager Tests

@Suite("AutomationManager")
struct AutomationManagerTests {

    @Test("activateForMeeting enables triggers and returns event stream")
    func activateForMeeting() async throws {
        let manager = AutomationManager(
            voiceTrigger: VoiceCommandTrigger(),
            keyboardTrigger: KeyboardShortcutTrigger(),
            undoStack: UndoStack()
        )

        let transcriptStream = AsyncStream<TranscriptSegment> { $0.finish() }
        let eventStream = await manager.activateForMeeting(
            meetingId: "meeting-1",
            transcriptStream: transcriptStream
        )

        let isActive = await manager.isActive
        #expect(isActive)

        // Event stream should finish since transcript was empty
        var events: [AutomationEvent] = []
        for await event in eventStream {
            events.append(event)
        }
        // No events expected from empty stream
        #expect(events.isEmpty)
    }

    @Test("deactivate stops triggers")
    func deactivateStopsTriggers() async throws {
        let manager = AutomationManager(
            voiceTrigger: VoiceCommandTrigger(),
            keyboardTrigger: KeyboardShortcutTrigger(),
            undoStack: UndoStack()
        )

        let transcriptStream = AsyncStream<TranscriptSegment> { $0.finish() }
        _ = await manager.activateForMeeting(
            meetingId: "meeting-1",
            transcriptStream: transcriptStream
        )
        await manager.deactivate()

        let isActive = await manager.isActive
        #expect(!isActive)
    }

    @Test("setEnabled controls whether triggers fire")
    func setEnabledControlsTriggers() async throws {
        let manager = AutomationManager(
            voiceTrigger: VoiceCommandTrigger(),
            keyboardTrigger: KeyboardShortcutTrigger(),
            undoStack: UndoStack()
        )

        await manager.setEnabled(false)
        let enabled = await manager.isEnabled
        #expect(!enabled)

        await manager.setEnabled(true)
        let enabledAgain = await manager.isEnabled
        #expect(enabledAgain)
    }

    @Test("undo delegates to UndoStack")
    func undoDelegatesToStack() async throws {
        let undoStack = UndoStack()
        let manager = AutomationManager(
            voiceTrigger: VoiceCommandTrigger(),
            keyboardTrigger: KeyboardShortcutTrigger(),
            undoStack: undoStack
        )

        let undoFlag = AutomationUndoFlag()
        await undoStack.push(UndoEntry(
            id: "undo-1",
            toolName: "remember",
            description: "Undo remember",
            timestamp: Date(),
            undoAction: { await undoFlag.set() }
        ))

        let result = try await manager.undo()
        #expect(result.toolName == "remember")

        let executed = await undoFlag.value
        #expect(executed)
    }

    @Test("undo on empty stack throws")
    func undoEmptyThrows() async throws {
        let manager = AutomationManager(
            voiceTrigger: VoiceCommandTrigger(),
            keyboardTrigger: KeyboardShortcutTrigger(),
            undoStack: UndoStack()
        )

        do {
            _ = try await manager.undo()
            #expect(Bool(false), "Expected UndoError.emptyStack")
        } catch is UndoError {
            // Expected
        }
    }

    @Test("keyboard trigger events flow through manager when active")
    func keyboardEventsFlowThrough() async throws {
        let keyboardTrigger = KeyboardShortcutTrigger()
        let manager = AutomationManager(
            voiceTrigger: VoiceCommandTrigger(),
            keyboardTrigger: keyboardTrigger,
            undoStack: UndoStack()
        )

        let transcriptStream = AsyncStream<TranscriptSegment> { $0.finish() }
        _ = await manager.activateForMeeting(
            meetingId: "meeting-1",
            transcriptStream: transcriptStream
        )

        // Keyboard trigger should be active now
        let kbActive = await keyboardTrigger.isActive
        #expect(kbActive)
    }

    @Test("canUndo reflects UndoStack state")
    func canUndoReflectsStack() async throws {
        let undoStack = UndoStack()
        let manager = AutomationManager(
            voiceTrigger: VoiceCommandTrigger(),
            keyboardTrigger: KeyboardShortcutTrigger(),
            undoStack: undoStack
        )

        let canUndoBefore = await manager.canUndo
        #expect(!canUndoBefore)

        await undoStack.push(UndoEntry(
            id: "undo-1",
            toolName: "remember",
            description: "Undo",
            timestamp: Date(),
            undoAction: {}
        ))

        let canUndoAfter = await manager.canUndo
        #expect(canUndoAfter)
    }
}

/// Thread-safe flag for use in @Sendable undo closures during testing.
private actor AutomationUndoFlag {
    var value: Bool = false
    func set() { value = true }
}

