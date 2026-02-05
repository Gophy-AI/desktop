import Foundation

public enum MeetingImportError: Error, LocalizedError {
    case invalidFileFormat
    case unsupportedVersion(Int)
    case missingRequiredFields
    case databaseError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidFileFormat:
            return "Invalid file format. Expected a .gophy.json file."
        case .unsupportedVersion(let version):
            return "Unsupported file version: \(version). This app only supports version 1."
        case .missingRequiredFields:
            return "The file is missing required fields."
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
}

public final class MeetingImporter: Sendable {
    private let meetingRepository: MeetingRepository
    private let embeddingPipeline: EmbeddingPipeline

    public init(
        meetingRepository: MeetingRepository,
        embeddingPipeline: EmbeddingPipeline
    ) {
        self.meetingRepository = meetingRepository
        self.embeddingPipeline = embeddingPipeline
    }

    public func importMeeting(from url: URL) async throws -> MeetingRecord {
        guard url.pathExtension == "json" || url.path.hasSuffix(".gophy.json") else {
            throw MeetingImportError.invalidFileFormat
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MeetingImportError.invalidFileFormat
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let exported: ExportedMeeting
        do {
            exported = try decoder.decode(ExportedMeeting.self, from: data)
        } catch {
            throw MeetingImportError.invalidFileFormat
        }

        guard exported.version == 1 else {
            throw MeetingImportError.unsupportedVersion(exported.version)
        }

        let meeting = MeetingRecord(
            id: exported.meeting.id,
            title: exported.meeting.title,
            startedAt: exported.meeting.startedAt,
            endedAt: exported.meeting.endedAt,
            mode: exported.meeting.mode,
            status: exported.meeting.status,
            createdAt: exported.meeting.createdAt
        )

        do {
            try await meetingRepository.create(meeting)
        } catch {
            throw MeetingImportError.databaseError(error)
        }

        for exportedSegment in exported.transcript {
            let segment = TranscriptSegmentRecord(
                id: exportedSegment.id,
                meetingId: exportedSegment.meetingId,
                text: exportedSegment.text,
                speaker: exportedSegment.speaker,
                startTime: exportedSegment.startTime,
                endTime: exportedSegment.endTime,
                createdAt: exportedSegment.createdAt
            )

            do {
                try await meetingRepository.addTranscriptSegment(segment)
            } catch {
                throw MeetingImportError.databaseError(error)
            }
        }

        do {
            try await embeddingPipeline.indexMeeting(meetingId: meeting.id)
        } catch {
            // Log error but don't fail import if indexing fails
            print("Warning: Failed to index meeting during import: \(error)")
        }

        return meeting
    }
}
