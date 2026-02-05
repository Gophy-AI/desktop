import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case meetings = "Meetings"
    case documents = "Documents"
    case chat = "Chat"
    case models = "Models"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .meetings:
            return "person.3"
        case .documents:
            return "doc.text"
        case .chat:
            return "bubble.left.and.bubble.right"
        case .models:
            return "cpu"
        case .settings:
            return "gear"
        }
    }
}

@MainActor
struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selectedItem) { item in
            NavigationLink(value: item) {
                Label(item.rawValue, systemImage: item.icon)
            }
        }
        .navigationTitle("Gophy")
        .frame(minWidth: 200)
    }
}
