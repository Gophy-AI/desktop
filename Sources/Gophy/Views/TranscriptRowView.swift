import SwiftUI

@MainActor
struct TranscriptRowView: View {
    let segment: TranscriptSegmentRecord
    let meetingStartTime: Date

    private var relativeTime: String {
        let seconds = Int(segment.startTime)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private var speakerColor: Color {
        if segment.speaker.lowercased() == "you" || segment.speaker.lowercased() == "user" {
            return .blue
        } else {
            return .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(segment.speaker)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(speakerColor)

                    Text(relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

#Preview {
    VStack(spacing: 0) {
        TranscriptRowView(
            segment: TranscriptSegmentRecord(
                id: "1",
                meetingId: "meeting1",
                text: "Hello, how are you doing today?",
                speaker: "You",
                startTime: 15.0,
                endTime: 18.0,
                createdAt: Date()
            ),
            meetingStartTime: Date()
        )

        Divider()

        TranscriptRowView(
            segment: TranscriptSegmentRecord(
                id: "2",
                meetingId: "meeting1",
                text: "I'm doing well, thanks for asking. How about you?",
                speaker: "Speaker 2",
                startTime: 20.0,
                endTime: 24.0,
                createdAt: Date()
            ),
            meetingStartTime: Date()
        )
    }
    .frame(width: 400)
}
