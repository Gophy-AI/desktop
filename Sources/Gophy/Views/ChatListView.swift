import SwiftUI

@MainActor
struct ChatListView: View {
    @Bindable var viewModel: ChatListViewModel
    @Binding var selectedChatId: String?
    @State private var renamingChatId: String?
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            newChatButton

            Divider()

            chatList
        }
        .frame(width: 250)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search chats...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .padding(8)
    }

    private var newChatButton: some View {
        Button {
            viewModel.showNewChatPicker = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("New Chat")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .confirmationDialog("New Chat Scope", isPresented: $viewModel.showNewChatPicker) {
            Button("All") {
                Task {
                    let chat = await viewModel.createChat(title: "New Chat", contextType: .all, contextId: nil)
                    if let chat {
                        selectedChatId = chat.id
                    }
                }
            }
            Button("Meetings") {
                Task {
                    let chat = await viewModel.createChat(title: "Meetings Chat", contextType: .meetings, contextId: nil)
                    if let chat {
                        selectedChatId = chat.id
                    }
                }
            }
            Button("Documents") {
                Task {
                    let chat = await viewModel.createChat(title: "Documents Chat", contextType: .documents, contextId: nil)
                    if let chat {
                        selectedChatId = chat.id
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var chatList: some View {
        List(selection: $selectedChatId) {
            if !viewModel.predefinedChats.isEmpty {
                Section("Pinned") {
                    ForEach(viewModel.predefinedChats) { chat in
                        chatRow(chat)
                            .tag(chat.id)
                            .contextMenu {
                                Button("Clear Messages") {
                                    NotificationCenter.default.post(
                                        name: .clearChatMessages,
                                        object: nil,
                                        userInfo: ["chatId": chat.id]
                                    )
                                }
                            }
                    }
                }
            }

            if !viewModel.userChats.isEmpty {
                Section("Chats") {
                    ForEach(viewModel.userChats) { chat in
                        chatRow(chat)
                            .tag(chat.id)
                            .contextMenu {
                                Button("Rename") {
                                    renamingChatId = chat.id
                                    renameText = chat.title
                                }
                                Button("Delete", role: .destructive) {
                                    Task {
                                        await viewModel.deleteChat(id: chat.id)
                                        if selectedChatId == chat.id {
                                            selectedChatId = viewModel.predefinedChats.first?.id
                                        }
                                    }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .alert("Rename Chat", isPresented: Binding(
            get: { renamingChatId != nil },
            set: { if !$0 { renamingChatId = nil } }
        )) {
            TextField("Chat name", text: $renameText)
            Button("Rename") {
                if let id = renamingChatId {
                    Task {
                        await viewModel.renameChat(id: id, title: renameText)
                    }
                }
                renamingChatId = nil
            }
            Button("Cancel", role: .cancel) {
                renamingChatId = nil
            }
        }
    }

    private func chatRow(_ chat: ChatRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: chat.chatContextType?.displayIcon ?? "bubble.left.and.bubble.right")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.body)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

extension Notification.Name {
    static let clearChatMessages = Notification.Name("clearChatMessages")
}
