import Foundation
import SwiftUI

@MainActor
@Observable
public final class MeetingHistoryViewModel {
    private let meetingRepository: MeetingRepository

    public var meetings: [MeetingRecord] = []
    public var searchQuery: String = ""
    public var errorMessage: String?
    public var isLoading = false
    public var showDeleteConfirmation = false
    public var meetingToDelete: MeetingRecord?

    public init(meetingRepository: MeetingRepository) {
        self.meetingRepository = meetingRepository
    }

    public var filteredMeetings: [MeetingRecord] {
        if searchQuery.isEmpty {
            return meetings
        } else {
            return meetings.filter { meeting in
                meeting.title.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    public func loadMeetings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try await meetingRepository.listAll()
        } catch {
            errorMessage = "Failed to load meetings: \(error.localizedDescription)"
        }
    }

    public func searchMeetings() async {
        guard !searchQuery.isEmpty else {
            await loadMeetings()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try await meetingRepository.search(query: searchQuery)
        } catch {
            errorMessage = "Failed to search meetings: \(error.localizedDescription)"
        }
    }

    public func confirmDelete(_ meeting: MeetingRecord) {
        meetingToDelete = meeting
        showDeleteConfirmation = true
    }

    public func deleteMeeting() async {
        guard let meeting = meetingToDelete else { return }

        do {
            try await meetingRepository.delete(id: meeting.id)
            meetings.removeAll { $0.id == meeting.id }
            meetingToDelete = nil
            showDeleteConfirmation = false
        } catch {
            errorMessage = "Failed to delete meeting: \(error.localizedDescription)"
            showDeleteConfirmation = false
        }
    }

    public func cancelDelete() {
        meetingToDelete = nil
        showDeleteConfirmation = false
    }

    public func formatDuration(_ meeting: MeetingRecord) -> String {
        guard let endedAt = meeting.endedAt else {
            return "--:--"
        }

        let duration = Int(endedAt.timeIntervalSince(meeting.startedAt))
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
