import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "AutomationManager")

/// Coordinates all automation subsystems (voice triggers, keyboard shortcuts, undo)
/// and integrates with the meeting lifecycle.
public actor AutomationManager {
    private let voiceTrigger: VoiceCommandTrigger
    private let keyboardTrigger: KeyboardShortcutTrigger
    private let undoStack: UndoStack

    private var activeMeetingId: String?
    private var voiceMonitorTask: Task<Void, Never>?
    private var enabled: Bool = true

    public var isActive: Bool {
        activeMeetingId != nil
    }

    public var isEnabled: Bool {
        enabled
    }

    public var canUndo: Bool {
        get async { await undoStack.canUndo }
    }

    public init(
        voiceTrigger: VoiceCommandTrigger,
        keyboardTrigger: KeyboardShortcutTrigger,
        undoStack: UndoStack
    ) {
        self.voiceTrigger = voiceTrigger
        self.keyboardTrigger = keyboardTrigger
        self.undoStack = undoStack
    }

    /// Activate automation for a meeting session.
    ///
    /// - Parameters:
    ///   - meetingId: The active meeting identifier.
    ///   - transcriptStream: Stream of transcript segments for voice command detection.
    /// - Returns: A stream of automation events from all trigger sources.
    public func activateForMeeting(
        meetingId: String,
        transcriptStream: AsyncStream<TranscriptSegment>
    ) async -> AsyncStream<AutomationEvent> {
        activeMeetingId = meetingId

        // Activate keyboard shortcuts
        await keyboardTrigger.activate(meetingId: meetingId)

        logger.info("Automations activated for meeting: \(meetingId, privacy: .public)")

        let voiceTrigger = self.voiceTrigger
        let enabled = self.enabled

        return AsyncStream { continuation in
            let task = Task {
                guard enabled else {
                    continuation.finish()
                    return
                }

                let voiceEvents = await voiceTrigger.monitor(
                    transcriptStream: transcriptStream,
                    meetingId: meetingId
                )

                for await event in voiceEvents {
                    continuation.yield(event)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Deactivate all automation triggers.
    public func deactivate() async {
        let meetingId = activeMeetingId
        activeMeetingId = nil

        voiceMonitorTask?.cancel()
        voiceMonitorTask = nil

        await keyboardTrigger.deactivate()

        if let meetingId {
            logger.info("Automations deactivated for meeting: \(meetingId, privacy: .public)")
        }
    }

    /// Undo the most recent automation action.
    public func undo() async throws -> UndoResult {
        try await undoStack.undo()
    }

    /// Push an undo entry after a successful tool execution.
    public func pushUndo(_ entry: UndoEntry) async {
        await undoStack.push(entry)
    }

    /// Enable or disable automations.
    public func setEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        if !enabled {
            await deactivate()
        }
    }
}

/// Protocol for the automation subsystem, used by MeetingSessionController.
public protocol AutomationManaging: Sendable {
    func activateForMeeting(
        meetingId: String,
        transcriptStream: AsyncStream<TranscriptSegment>
    ) async -> AsyncStream<AutomationEvent>
    func deactivate() async
}

extension AutomationManager: AutomationManaging {}
