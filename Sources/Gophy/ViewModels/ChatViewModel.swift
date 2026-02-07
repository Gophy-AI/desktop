import Foundation
import SwiftUI

public struct ChatMessage: Identifiable, Sendable {
    public let id: String
    public let role: String
    public let content: String
    public let createdAt: Date

    public init(id: String, role: String, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
public final class ChatViewModel {
    public var messages: [ChatMessage] = []
    public var inputText: String = ""
    public var selectedScope: RAGScope = .all
    public var isGenerating: Bool = false
    public var errorMessage: String?

    public let meetingId: String?
    public let documentId: String?

    private let ragPipeline: RAGPipeline
    private let chatMessageRepository: ChatMessageRepository

    public init(
        ragPipeline: RAGPipeline,
        chatMessageRepository: ChatMessageRepository,
        meetingId: String? = nil,
        documentId: String? = nil
    ) {
        self.ragPipeline = ragPipeline
        self.chatMessageRepository = chatMessageRepository
        self.meetingId = meetingId
        self.documentId = documentId

        if let meetingId {
            self.selectedScope = .meeting(id: meetingId)
        } else if let documentId {
            self.selectedScope = .document(id: documentId)
        }
    }

    public func loadMessages() async {
        do {
            let records: [ChatMessageRecord]
            if let meetingId {
                records = try await chatMessageRepository.listForMeeting(meetingId: meetingId)
            } else {
                records = try await chatMessageRepository.listGlobal()
            }
            messages = records.map {
                ChatMessage(id: $0.id, role: $0.role, content: $0.content, createdAt: $0.createdAt)
            }
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }

    public func sendMessage() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: inputText,
            createdAt: Date()
        )

        messages.append(userMessage)

        let userRecord = ChatMessageRecord(
            id: userMessage.id,
            role: userMessage.role,
            content: userMessage.content,
            meetingId: meetingId,
            createdAt: userMessage.createdAt
        )

        do {
            try await chatMessageRepository.create(userRecord)
        } catch {
            errorMessage = "Failed to save message: \(error.localizedDescription)"
        }

        let question = inputText
        inputText = ""
        isGenerating = true

        let assistantId = UUID().uuidString
        var assistantContent = ""

        let assistantMessage = ChatMessage(
            id: assistantId,
            role: "assistant",
            content: "",
            createdAt: Date()
        )
        messages.append(assistantMessage)

        let responseStream = ragPipeline.query(question: question, scope: selectedScope)

        for await token in responseStream {
            assistantContent += token

            if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[index] = ChatMessage(
                    id: assistantId,
                    role: "assistant",
                    content: assistantContent,
                    createdAt: assistantMessage.createdAt
                )
            }
        }

        isGenerating = false

        let assistantRecord = ChatMessageRecord(
            id: assistantId,
            role: "assistant",
            content: assistantContent,
            meetingId: meetingId,
            createdAt: assistantMessage.createdAt
        )

        do {
            try await chatMessageRepository.create(assistantRecord)
        } catch {
            errorMessage = "Failed to save assistant message: \(error.localizedDescription)"
        }
    }

    public func clearMessages() async {
        for message in messages {
            do {
                try await chatMessageRepository.delete(id: message.id)
            } catch {
                print("Failed to delete message \(message.id): \(error)")
            }
        }
        messages.removeAll()
    }

    public func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
