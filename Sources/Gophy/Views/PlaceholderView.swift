import SwiftUI

@MainActor
struct PlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: item.icon)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(item.rawValue)
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
