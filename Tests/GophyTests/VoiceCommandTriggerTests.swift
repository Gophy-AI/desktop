import Testing
import Foundation
import MLXLMCommon
@testable import Gophy

// MARK: - VoiceCommandTrigger Tests

@Suite("VoiceCommandTrigger")
struct VoiceCommandTriggerTests {

    @Test("'remember this' pattern triggers remember action")
    func rememberThisPatternTriggers() async throws {
        let trigger = VoiceCommandTrigger()

        let segment = TranscriptSegment(
            text: "We should remember this for later",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggeredTools: [String] = []
        for await event in eventStream {
            if case .triggered(let toolName, _) = event {
                triggeredTools.append(toolName)
            }
        }

        #expect(triggeredTools.contains("remember"))
    }

    @Test("'take a note' pattern triggers take_note action")
    func takeNotePatternTriggers() async throws {
        let trigger = VoiceCommandTrigger()

        let segment = TranscriptSegment(
            text: "Please take a note about this",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggeredTools: [String] = []
        for await event in eventStream {
            if case .triggered(let toolName, _) = event {
                triggeredTools.append(toolName)
            }
        }

        #expect(triggeredTools.contains("take_note"))
    }

    @Test("'summarize the meeting' triggers generate_summary action")
    func summarizePatternTriggers() async throws {
        let trigger = VoiceCommandTrigger()

        let segment = TranscriptSegment(
            text: "Can you summarize the meeting",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggeredTools: [String] = []
        for await event in eventStream {
            if case .triggered(let toolName, _) = event {
                triggeredTools.append(toolName)
            }
        }

        #expect(triggeredTools.contains("generate_summary"))
    }

    @Test("'search for <query>' triggers search_knowledge with extracted query")
    func searchPatternTriggersWithQuery() async throws {
        let trigger = VoiceCommandTrigger()

        let segment = TranscriptSegment(
            text: "search for project timeline",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggeredTools: [String] = []
        for await event in eventStream {
            if case .triggered(let toolName, _) = event {
                triggeredTools.append(toolName)
            }
        }

        #expect(triggeredTools.contains("search_knowledge"))
    }

    @Test("patterns are case-insensitive")
    func caseInsensitiveMatching() async throws {
        let trigger = VoiceCommandTrigger()

        let segment = TranscriptSegment(
            text: "REMEMBER THIS please",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggeredTools: [String] = []
        for await event in eventStream {
            if case .triggered(let toolName, _) = event {
                triggeredTools.append(toolName)
            }
        }

        #expect(triggeredTools.contains("remember"))
    }

    @Test("partial matches do not trigger (e.g., 'I remember that' should not trigger)")
    func partialMatchesDoNotTrigger() async throws {
        let trigger = VoiceCommandTrigger()

        let segment = TranscriptSegment(
            text: "I remember that from last week",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggeredTools: [String] = []
        for await event in eventStream {
            if case .triggered(let toolName, _) = event {
                triggeredTools.append(toolName)
            }
        }

        #expect(!triggeredTools.contains("remember"))
    }

    @Test("cooldown prevents re-triggering within 5 seconds")
    func cooldownPreventsRetrigger() async throws {
        let trigger = VoiceCommandTrigger()

        let segment1 = TranscriptSegment(
            text: "remember this",
            startTime: 0.0,
            endTime: 1.0,
            speaker: "You"
        )
        let segment2 = TranscriptSegment(
            text: "remember this again",
            startTime: 1.0,
            endTime: 2.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment1)
        continuation.yield(segment2)
        continuation.finish()

        var triggerCount = 0
        for await event in eventStream {
            if case .triggered(let toolName, _) = event, toolName == "remember" {
                triggerCount += 1
            }
        }

        // Only the first should trigger due to cooldown
        #expect(triggerCount == 1)
    }

    @Test("custom patterns can be registered")
    func customPatternRegistered() async throws {
        let trigger = VoiceCommandTrigger()

        let customPattern = VoicePattern(
            regex: try Regex("(?i)\\bhelp me\\b"),
            toolName: "custom_help",
            extractArgs: { _ in [:] },
            description: "Custom help command"
        )
        await trigger.registerPattern(customPattern)

        let segment = TranscriptSegment(
            text: "help me with this",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggeredTools: [String] = []
        for await event in eventStream {
            if case .triggered(let toolName, _) = event {
                triggeredTools.append(toolName)
            }
        }

        #expect(triggeredTools.contains("custom_help"))
    }

    @Test("disabled trigger does not fire")
    func disabledTriggerDoesNotFire() async throws {
        let trigger = VoiceCommandTrigger()
        await trigger.setEnabled(false)

        let segment = TranscriptSegment(
            text: "remember this",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var triggerCount = 0
        for await event in eventStream {
            if case .triggered = event { triggerCount += 1 }
        }

        #expect(triggerCount == 0)
    }

    @Test("trigger source is voiceCommand")
    func triggerSourceIsVoiceCommand() async throws {
        let trigger = VoiceCommandTrigger()

        let segment = TranscriptSegment(
            text: "take a note",
            startTime: 0.0,
            endTime: 3.0,
            speaker: "You"
        )

        let (transcriptStream, continuation) = AsyncStream<TranscriptSegment>.makeStream()

        let eventStream = await trigger.monitor(
            transcriptStream: transcriptStream,
            meetingId: "meeting-1"
        )

        continuation.yield(segment)
        continuation.finish()

        var sources: [TriggerSource] = []
        for await event in eventStream {
            if case .triggered(_, let source) = event {
                sources.append(source)
            }
        }

        #expect(sources.allSatisfy { $0 == .voiceCommand })
    }
}
