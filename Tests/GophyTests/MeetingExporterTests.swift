import XCTest
@testable import Gophy
import Foundation

final class MeetingExporterTests: XCTestCase {
    func testJSONExportContainsValidJSON() async throws {
        let meeting = MeetingRecord(
            id: "test-meeting-1",
            title: "Test Meeting",
            startedAt: Date(timeIntervalSince1970: 1000000000),
            endedAt: Date(timeIntervalSince1970: 1000003600),
            mode: "microphone",
            status: "completed",
            createdAt: Date(timeIntervalSince1970: 1000000000)
        )

        let segments = [
            TranscriptSegmentRecord(
                id: "seg-1",
                meetingId: "test-meeting-1",
                text: "Hello world",
                speaker: "User",
                startTime: 0.0,
                endTime: 2.5,
                createdAt: Date(timeIntervalSince1970: 1000000000)
            ),
            TranscriptSegmentRecord(
                id: "seg-2",
                meetingId: "test-meeting-1",
                text: "This is a test",
                speaker: "System",
                startTime: 2.5,
                endTime: 5.0,
                createdAt: Date(timeIntervalSince1970: 1000000001)
            )
        ]

        let suggestions = ["First suggestion", "Second suggestion"]

        let exporter = MeetingExporter()
        let jsonData = try exporter.exportJSON(
            meeting: meeting,
            transcript: segments,
            suggestions: suggestions
        )

        // Verify it's valid JSON
        let decoded = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        XCTAssertNotNil(decoded)

        // Verify version
        XCTAssertEqual(decoded?["version"] as? Int, 1)

        // Verify meeting data
        let meetingData = decoded?["meeting"] as? [String: Any]
        XCTAssertNotNil(meetingData)
        XCTAssertEqual(meetingData?["id"] as? String, "test-meeting-1")
        XCTAssertEqual(meetingData?["title"] as? String, "Test Meeting")
        XCTAssertEqual(meetingData?["mode"] as? String, "microphone")
        XCTAssertEqual(meetingData?["status"] as? String, "completed")

        // Verify transcript
        let transcript = decoded?["transcript"] as? [[String: Any]]
        XCTAssertEqual(transcript?.count, 2)
        XCTAssertEqual(transcript?[0]["text"] as? String, "Hello world")
        XCTAssertEqual(transcript?[0]["speaker"] as? String, "User")

        // Verify suggestions
        let savedSuggestions = decoded?["suggestions"] as? [String]
        XCTAssertEqual(savedSuggestions?.count, 2)
        XCTAssertEqual(savedSuggestions?[0], "First suggestion")
    }

    func testMarkdownExportHasCorrectFormatting() async throws {
        let meeting = MeetingRecord(
            id: "test-meeting-2",
            title: "Markdown Test",
            startedAt: Date(timeIntervalSince1970: 1000000000),
            endedAt: Date(timeIntervalSince1970: 1000003600),
            mode: "system-audio",
            status: "completed",
            createdAt: Date(timeIntervalSince1970: 1000000000)
        )

        let segments = [
            TranscriptSegmentRecord(
                id: "seg-1",
                meetingId: "test-meeting-2",
                text: "First line",
                speaker: "Speaker A",
                startTime: 0.0,
                endTime: 2.5,
                createdAt: Date(timeIntervalSince1970: 1000000000)
            ),
            TranscriptSegmentRecord(
                id: "seg-2",
                meetingId: "test-meeting-2",
                text: "Second line",
                speaker: "Speaker B",
                startTime: 2.5,
                endTime: 5.0,
                createdAt: Date(timeIntervalSince1970: 1000000001)
            ),
            TranscriptSegmentRecord(
                id: "seg-3",
                meetingId: "test-meeting-2",
                text: "Third line",
                speaker: "Speaker A",
                startTime: 125.3,
                endTime: 130.0,
                createdAt: Date(timeIntervalSince1970: 1000000002)
            )
        ]

        let suggestions = ["Suggestion one"]

        let exporter = MeetingExporter()
        let markdown = exporter.exportMarkdown(
            meeting: meeting,
            transcript: segments,
            suggestions: suggestions
        )

        // Check for title
        XCTAssertTrue(markdown.contains("# Markdown Test"))

        // Check for date
        XCTAssertTrue(markdown.contains("Date:"))

        // Check for duration
        XCTAssertTrue(markdown.contains("Duration:"))

        // Check for transcript header
        XCTAssertTrue(markdown.contains("## Transcript"))

        // Check for timestamp formatting (MM:SS)
        XCTAssertTrue(markdown.contains("[00:00]"))
        XCTAssertTrue(markdown.contains("[00:02]"))
        XCTAssertTrue(markdown.contains("[02:05]"))

        // Check for speaker names
        XCTAssertTrue(markdown.contains("**Speaker A**:"))
        XCTAssertTrue(markdown.contains("**Speaker B**:"))

        // Check for transcript content
        XCTAssertTrue(markdown.contains("First line"))
        XCTAssertTrue(markdown.contains("Second line"))

        // Check for suggestions section
        XCTAssertTrue(markdown.contains("## Suggestions"))
        XCTAssertTrue(markdown.contains("- Suggestion one"))
    }

    func testTimestampsFormattedAsMMSS() {
        let exporter = MeetingExporter()

        // Test various timestamps
        XCTAssertEqual(exporter.formatTimestamp(0.0), "00:00")
        XCTAssertEqual(exporter.formatTimestamp(59.9), "00:59")
        XCTAssertEqual(exporter.formatTimestamp(60.0), "01:00")
        XCTAssertEqual(exporter.formatTimestamp(125.3), "02:05")
        XCTAssertEqual(exporter.formatTimestamp(3599.9), "59:59")
        XCTAssertEqual(exporter.formatTimestamp(3661.0), "61:01")
    }

    func testRoundTripPreservesData() async throws {
        let meeting = MeetingRecord(
            id: "test-meeting-3",
            title: "Round Trip Test",
            startedAt: Date(timeIntervalSince1970: 1000000000),
            endedAt: Date(timeIntervalSince1970: 1000003600),
            mode: "microphone",
            status: "completed",
            createdAt: Date(timeIntervalSince1970: 1000000000)
        )

        let segments = [
            TranscriptSegmentRecord(
                id: "seg-1",
                meetingId: "test-meeting-3",
                text: "Test content",
                speaker: "TestUser",
                startTime: 10.5,
                endTime: 20.8,
                createdAt: Date(timeIntervalSince1970: 1000000000)
            )
        ]

        let suggestions = ["Test suggestion"]

        let exporter = MeetingExporter()
        let jsonData = try exporter.exportJSON(
            meeting: meeting,
            transcript: segments,
            suggestions: suggestions
        )

        // Parse it back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportedMeeting.self, from: jsonData)

        // Verify meeting data
        XCTAssertEqual(decoded.meeting.id, meeting.id)
        XCTAssertEqual(decoded.meeting.title, meeting.title)
        XCTAssertEqual(decoded.meeting.mode, meeting.mode)
        XCTAssertEqual(decoded.meeting.status, meeting.status)

        // Verify transcript
        XCTAssertEqual(decoded.transcript.count, 1)
        XCTAssertEqual(decoded.transcript[0].id, segments[0].id)
        XCTAssertEqual(decoded.transcript[0].text, segments[0].text)
        XCTAssertEqual(decoded.transcript[0].speaker, segments[0].speaker)
        XCTAssertEqual(decoded.transcript[0].startTime, segments[0].startTime, accuracy: 0.01)
        XCTAssertEqual(decoded.transcript[0].endTime, segments[0].endTime, accuracy: 0.01)

        // Verify suggestions
        XCTAssertEqual(decoded.suggestions, suggestions)

        // Verify version
        XCTAssertEqual(decoded.version, 1)
    }
}
