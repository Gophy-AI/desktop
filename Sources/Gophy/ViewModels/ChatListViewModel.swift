import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "ChatListViewModel")

@MainActor
@Observable
public final class ChatListViewModel {
    public var chats: [ChatRecord] = []
    public var searchText: String = ""
    public var selectedChatId: String?
    public var showNewChatPicker: Bool = false
    public var errorMessage: String?

    private let chatRepository: ChatRepository

    public init(chatRepository: ChatRepository) {
        self.chatRepository = chatRepository
    }

    public func loadChats() async {
        do {
            try await chatRepository.ensurePredefinedChatsExist()
            chats = try await chatRepository.listAll()
        } catch {
            logger.error("Failed to load chats: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Failed to load chats: \(error.localizedDescription)"
        }
    }

    public func createChat(title: String, contextType: ChatContextType, contextId: String?) async -> ChatRecord? {
        let now = Date()
        let chat = ChatRecord(
            id: UUID().uuidString,
            title: title,
            contextType: contextType.rawValue,
            contextId: contextId,
            isPredefined: false,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await chatRepository.create(chat)
            await loadChats()
            return chat
        } catch {
            logger.error("Failed to create chat: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Failed to create chat: \(error.localizedDescription)"
            return nil
        }
    }

    public func deleteChat(id: String) async {
        do {
            try await chatRepository.delete(id: id)
            await loadChats()
        } catch {
            logger.error("Failed to delete chat: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Failed to delete chat: \(error.localizedDescription)"
        }
    }

    public func renameChat(id: String, title: String) async {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return }
        var chat = chats[index]
        chat.title = title
        chat.updatedAt = Date()
        do {
            try await chatRepository.update(chat)
            await loadChats()
        } catch {
            logger.error("Failed to rename chat: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Failed to rename chat: \(error.localizedDescription)"
        }
    }

    public var filteredChats: [ChatRecord] {
        if searchText.isEmpty {
            return chats
        }
        return chats.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    public var predefinedChats: [ChatRecord] {
        filteredChats.filter { $0.isPredefined }
    }

    public var userChats: [ChatRecord] {
        filteredChats.filter { !$0.isPredefined }
    }
}
