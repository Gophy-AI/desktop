import Foundation

/// Monitors transcript segments and triggers automations when voice command patterns are detected.
public actor VoiceCommandTrigger {
    private var patterns: [VoicePattern]
    private var isEnabled: Bool = true
    private var lastTriggerTimes: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 5.0

    public init(patterns: [VoicePattern] = VoicePattern.defaults) {
        self.patterns = patterns
    }

    /// Register an additional voice pattern.
    public func registerPattern(_ pattern: VoicePattern) {
        patterns.append(pattern)
    }

    /// Enable or disable the trigger.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Monitor a transcript stream for voice commands and emit automation events.
    ///
    /// - Parameters:
    ///   - transcriptStream: The stream of transcript segments to monitor.
    ///   - meetingId: The ID of the active meeting.
    /// - Returns: A stream of automation events triggered by voice commands.
    public func monitor(
        transcriptStream: AsyncStream<TranscriptSegment>,
        meetingId: String
    ) -> AsyncStream<AutomationEvent> {
        let patterns = self.patterns
        let enabled = self.isEnabled
        let cooldown = self.cooldownInterval

        // Use a local copy of last trigger times that we'll manage in the task
        var localTriggerTimes: [String: Date] = self.lastTriggerTimes

        return AsyncStream { continuation in
            Task { [localTriggerTimes] in
                var triggerTimes = localTriggerTimes

                for await segment in transcriptStream {
                    guard enabled else { continue }

                    let now = Date()

                    for pattern in patterns {
                        // Check cooldown
                        if let lastTime = triggerTimes[pattern.toolName],
                           now.timeIntervalSince(lastTime) < cooldown {
                            continue
                        }

                        // Check if the pattern matches
                        if let match = segment.text.firstMatch(of: pattern.regex) {
                            triggerTimes[pattern.toolName] = now

                            let args = pattern.extractArgs(match)
                            _ = args // Arguments are extracted but the trigger only emits the event

                            continuation.yield(.triggered(
                                toolName: pattern.toolName,
                                source: .voiceCommand
                            ))
                        }
                    }
                }

                continuation.finish()
            }
        }
    }
}
