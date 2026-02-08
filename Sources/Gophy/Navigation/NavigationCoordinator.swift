import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "NavigationCoordinator")

@MainActor
@Observable
final class NavigationCoordinator {
    var selectedItem: SidebarItem?
    var selectedChatId: String?

    private var chatRepository: ChatRepository?
    private var database: GophyDatabase?

    init() {}

    func openChat(contextType: ChatContextType, contextId: String?, title: String) async {
        let repo = try? ensureChatRepository()
        guard let repo else { return }

        do {
            if let contextId, let existing = try await repo.findByContextId(contextId) {
                selectedChatId = existing.id
                selectedItem = .chat
                return
            }

            let now = Date()
            let newChat = ChatRecord(
                id: UUID().uuidString,
                title: title,
                contextType: contextType.rawValue,
                contextId: contextId,
                isPredefined: false,
                createdAt: now,
                updatedAt: now
            )
            try await repo.create(newChat)
            selectedChatId = newChat.id
            selectedItem = .chat
        } catch {
            logger.error("openChat failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func navigateToChat(_ chatId: String) {
        selectedChatId = chatId
        selectedItem = .chat
    }

    private func ensureChatRepository() throws -> ChatRepository {
        if let chatRepository {
            return chatRepository
        }

        let storageManager = StorageManager()
        let db = try GophyDatabase(storageManager: storageManager)
        let repo = ChatRepository(database: db)
        self.database = db
        self.chatRepository = repo
        return repo
    }
}
