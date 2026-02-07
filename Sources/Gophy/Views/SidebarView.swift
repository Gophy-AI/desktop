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
    var upcomingMeetingsViewModel: UpcomingMeetingsViewModel?
    var onStartRecording: ((UnifiedCalendarEvent) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.icon)
                }
            }
            .navigationTitle("Gophy")

            if let viewModel = upcomingMeetingsViewModel {
                Divider()

                UpcomingMeetingsView(
                    viewModel: viewModel,
                    onStartRecording: onStartRecording
                )
                .frame(maxHeight: 200)
            }
        }
        .frame(minWidth: 200)
    }
}
