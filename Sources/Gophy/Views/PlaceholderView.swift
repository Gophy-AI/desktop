import SwiftUI

@MainActor
struct PlaceholderView: View {
    let item: SidebarItem
    var selectedChatId: String?

    var body: some View {
        switch item {
        case .models:
            ModelManagerView()
        case .meetings:
            CalendarMeetingsView()
        case .documents:
            DocumentManagerView()
        case .chat:
            ChatView(initialChatId: selectedChatId)
                .id(selectedChatId ?? "default-chat")
        case .settings:
            SettingsView()
        }
    }
}
