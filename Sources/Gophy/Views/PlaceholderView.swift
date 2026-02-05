import SwiftUI

@MainActor
struct PlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        switch item {
        case .models:
            ModelManagerView()
        case .meetings:
            if let database = try? GophyDatabase(storageManager: StorageManager()) {
                let meetingRepo = MeetingRepository(database: database)
                let chatRepo = ChatMessageRepository(database: database)
                let viewModel = MeetingHistoryViewModel(meetingRepository: meetingRepo)
                MeetingHistoryView(
                    viewModel: viewModel,
                    meetingRepository: meetingRepo,
                    chatMessageRepository: chatRepo
                )
            } else {
                errorView
            }
        case .documents:
            DocumentManagerView()
        case .chat:
            ChatView()
        case .settings:
            SettingsView()
        }
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Database Error")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Failed to initialize database")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
