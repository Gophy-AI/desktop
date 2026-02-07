import Testing
import Foundation
@testable import Gophy

// MARK: - UndoStack Tests

@Suite("UndoStack")
struct UndoStackTests {

    @Test("push adds entry and canUndo becomes true")
    func pushAddsEntry() async throws {
        let stack = UndoStack()

        let canUndoBefore = await stack.canUndo
        #expect(!canUndoBefore)

        let entry = UndoEntry(
            id: "undo-1",
            toolName: "remember",
            description: "Undo remember",
            timestamp: Date(),
            undoAction: {}
        )
        await stack.push(entry)

        let canUndoAfter = await stack.canUndo
        #expect(canUndoAfter)

        let count = await stack.count
        #expect(count == 1)
    }

    @Test("undo pops and executes the most recent entry")
    func undoPopsAndExecutes() async throws {
        let stack = UndoStack()

        let firstFlag = UndoTestFlag()
        let secondFlag = UndoTestFlag()

        await stack.push(UndoEntry(
            id: "undo-1",
            toolName: "remember",
            description: "Undo first remember",
            timestamp: Date(),
            undoAction: { await firstFlag.set() }
        ))

        await stack.push(UndoEntry(
            id: "undo-2",
            toolName: "take_note",
            description: "Undo second note",
            timestamp: Date(),
            undoAction: { await secondFlag.set() }
        ))

        let result = try await stack.undo()
        #expect(result.toolName == "take_note")
        #expect(result.description == "Undo second note")

        let secondExecuted = await secondFlag.value
        #expect(secondExecuted)

        let firstExecuted = await firstFlag.value
        #expect(!firstExecuted)

        let count = await stack.count
        #expect(count == 1)
    }

    @Test("undo on empty stack throws emptyStack error")
    func undoEmptyStackThrows() async throws {
        let stack = UndoStack()

        do {
            _ = try await stack.undo()
            #expect(Bool(false), "Expected UndoError.emptyStack")
        } catch let error as UndoError {
            #expect(error == .emptyStack)
        }
    }

    @Test("stack limit evicts oldest entry when exceeding 50")
    func stackLimitEvictsOldest() async throws {
        let stack = UndoStack()

        // Push 55 entries
        for i in 0..<55 {
            await stack.push(UndoEntry(
                id: "undo-\(i)",
                toolName: "tool-\(i)",
                description: "Entry \(i)",
                timestamp: Date(),
                undoAction: {}
            ))
        }

        let count = await stack.count
        #expect(count == 50)

        // The most recent entry should be tool-54 (the last pushed)
        let result = try await stack.undo()
        #expect(result.toolName == "tool-54")
    }

    @Test("canUndo returns false after undoing all entries")
    func canUndoReturnsFalseAfterAll() async throws {
        let stack = UndoStack()

        await stack.push(UndoEntry(
            id: "undo-1",
            toolName: "remember",
            description: "Undo",
            timestamp: Date(),
            undoAction: {}
        ))

        _ = try await stack.undo()

        let canUndo = await stack.canUndo
        #expect(!canUndo)
    }

    @Test("clear removes all entries")
    func clearRemovesAll() async throws {
        let stack = UndoStack()

        for i in 0..<5 {
            await stack.push(UndoEntry(
                id: "undo-\(i)",
                toolName: "tool",
                description: "Entry \(i)",
                timestamp: Date(),
                undoAction: {}
            ))
        }

        await stack.clear()

        let count = await stack.count
        #expect(count == 0)

        let canUndo = await stack.canUndo
        #expect(!canUndo)
    }

    @Test("multiple undos pop in LIFO order")
    func multipleUndosLIFO() async throws {
        let stack = UndoStack()

        await stack.push(UndoEntry(
            id: "undo-1",
            toolName: "first",
            description: "First",
            timestamp: Date(),
            undoAction: {}
        ))

        await stack.push(UndoEntry(
            id: "undo-2",
            toolName: "second",
            description: "Second",
            timestamp: Date(),
            undoAction: {}
        ))

        await stack.push(UndoEntry(
            id: "undo-3",
            toolName: "third",
            description: "Third",
            timestamp: Date(),
            undoAction: {}
        ))

        let r1 = try await stack.undo()
        #expect(r1.toolName == "third")

        let r2 = try await stack.undo()
        #expect(r2.toolName == "second")

        let r3 = try await stack.undo()
        #expect(r3.toolName == "first")
    }
}

/// Thread-safe flag for use in @Sendable undo closures during testing.
private actor UndoTestFlag {
    var value: Bool = false
    func set() { value = true }
}
