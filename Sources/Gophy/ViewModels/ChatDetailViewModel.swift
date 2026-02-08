import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "ChatDetailViewModel")

@MainActor
@Observable
public final class ChatDetailViewModel {
    public var messages: [ChatMessage] = []
    public var inputText: String = ""
    public var isGenerating: Bool = false
    public var errorMessage: String?

    public let chat: ChatRecord

    private let ragPipeline: RAGPipeline
    private let chatMessageRepository: ChatMessageRepository
    private let chatRepository: ChatRepository

    public init(
        chat: ChatRecord,
        chatMessageRepository: ChatMessageRepository,
        chatRepository: ChatRepository,
        ragPipeline: RAGPipeline
    ) {
        self.chat = chat
        self.chatMessageRepository = chatMessageRepository
        self.chatRepository = chatRepository
        self.ragPipeline = ragPipeline
    }

    public func loadMessages() async {
        do {
            let records = try await chatMessageRepository.listForChat(chatId: chat.id)
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
            meetingId: meetingIdFromChat,
            chatId: chat.id,
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

        let scope = chat.ragScope
        let responseStream = ragPipeline.query(question: question, scope: scope)

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

        if assistantContent.isEmpty {
            messages.removeAll { $0.id == assistantId }
            errorMessage = "Failed to generate a response. Make sure models are downloaded."
            isGenerating = false
            return
        }

        isGenerating = false

        let assistantRecord = ChatMessageRecord(
            id: assistantId,
            role: "assistant",
            content: assistantContent,
            meetingId: meetingIdFromChat,
            chatId: chat.id,
            createdAt: assistantMessage.createdAt
        )

        do {
            try await chatMessageRepository.create(assistantRecord)
        } catch {
            errorMessage = "Failed to save assistant message: \(error.localizedDescription)"
        }

        var updatedChat = chat
        updatedChat.updatedAt = Date()
        do {
            try await chatRepository.update(updatedChat)
        } catch {
            // Non-fatal: chat timestamp update failure does not block messaging
        }
    }

    public func clearMessages() async {
        do {
            try await chatMessageRepository.deleteAllForChat(chatId: chat.id)
            messages.removeAll()
        } catch {
            errorMessage = "Failed to clear messages: \(error.localizedDescription)"
        }
    }

    public func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var meetingIdFromChat: String? {
        if chat.chatContextType == .meeting {
            return chat.contextId
        }
        return nil
    }
}
