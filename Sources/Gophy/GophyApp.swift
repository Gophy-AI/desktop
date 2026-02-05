import SwiftUI

@main
struct GophyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Gophy") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Gophy")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI-powered call assistant")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}

#Preview {
    ContentView()
}
