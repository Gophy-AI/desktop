import Foundation

/// A bounded stack of reversible automation actions.
///
/// Stores up to `maxEntries` (default 50) undo entries with FIFO eviction.
/// When the limit is reached, the oldest entry is discarded to make room.
public actor UndoStack {
    private var entries: [UndoEntry] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 50) {
        self.maxEntries = maxEntries
    }

    /// Push an undo entry onto the stack.
    public func push(_ entry: UndoEntry) {
        entries.append(entry)

        // FIFO eviction: remove oldest if over limit
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// Pop and execute the most recent undo action.
    ///
    /// - Returns: An `UndoResult` describing what was undone.
    /// - Throws: `UndoError.emptyStack` if there is nothing to undo.
    public func undo() async throws -> UndoResult {
        guard let entry = entries.popLast() else {
            throw UndoError.emptyStack
        }

        do {
            try await entry.undoAction()
        } catch {
            throw UndoError.undoFailed(
                toolName: entry.toolName,
                reason: error.localizedDescription
            )
        }

        return UndoResult(
            toolName: entry.toolName,
            description: entry.description
        )
    }

    /// Whether there are any entries that can be undone.
    public var canUndo: Bool {
        !entries.isEmpty
    }

    /// The number of entries in the stack.
    public var count: Int {
        entries.count
    }

    /// Remove all entries from the stack.
    public func clear() {
        entries.removeAll()
    }
}
