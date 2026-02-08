import SwiftUI

struct ScopedChatContext: Identifiable {
    let id: String
    let title: String
    let contextType: ChatContextType
}

@MainActor
struct ScopedChatSheetView: View {
    let context: ScopedChatContext
    @Environment(\.dismiss) private var dismiss

    @State private var database: GophyDatabase?
    @State private var chat: ChatRecord?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let database, let chat {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    ChatDetailView(chat: chat, database: database)
                }
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SwiftUI.ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await initialize()
        }
    }

    private func initialize() async {
        do {
            let storageManager = StorageManager()
            let db = try GophyDatabase(storageManager: storageManager)
            let chatRepo = ChatRepository(database: db)

            try await chatRepo.ensurePredefinedChatsExist()

            let existing = try await chatRepo.findByContextId(context.id)
            let record: ChatRecord
            if let existing {
                record = existing
            } else {
                let now = Date()
                record = ChatRecord(
                    id: UUID().uuidString,
                    title: context.title,
                    contextType: context.contextType.rawValue,
                    contextId: context.id,
                    isPredefined: false,
                    createdAt: now,
                    updatedAt: now
                )
                try await chatRepo.create(record)
            }

            database = db
            chat = record
        } catch {
            loadError = "Failed to load chat: \(error.localizedDescription)"
        }
    }
}
