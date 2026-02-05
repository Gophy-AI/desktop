import SwiftUI

@main
struct GophyApp: App {
    @State private var selectedItem: SidebarItem? = .meetings

    var body: some Scene {
        WindowGroup {
            ContentView(selectedItem: $selectedItem)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Gophy") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
        }

        MenuBarExtra("Gophy", systemImage: "phone.circle.fill") {
            Button("Show Gophy") {
                activateApp()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
struct ContentView: View {
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedItem)
        } detail: {
            if let item = selectedItem {
                PlaceholderView(item: item)
            } else {
                VStack(spacing: 20) {
                    Text("Gophy")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("AI-powered call assistant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView(selectedItem: .constant(.meetings))
}
