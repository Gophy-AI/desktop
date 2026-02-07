import SwiftUI

@MainActor
struct PlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        switch item {
        case .models:
            ModelManagerView()
        case .meetings:
            CalendarMeetingsView()
        case .documents:
            DocumentManagerView()
        case .chat:
            ChatView()
        case .settings:
            SettingsView()
        }
    }
}
