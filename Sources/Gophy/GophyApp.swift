import SwiftUI

@main
struct GophyApp: App {
    @State private var selectedItem: SidebarItem? = .meetings
    @State private var showOnboarding: Bool = !OnboardingViewModel.hasCompletedOnboarding()

    init() {
        // Install crash reporter as early as possible
        CrashReporter.shared.install()
        CrashReporter.shared.logInfo("GophyApp initializing")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(selectedItem: $selectedItem)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView {
                        showOnboarding = false
                    }
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Gophy") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }

            CommandGroup(after: .newItem) {
                Button("New Meeting") {
                    selectedItem = .meetings
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Import Recording") {
                    selectedItem = .recordings
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
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
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedItem: $selectedItem
            )
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
        .onAppear {
            setupKeyboardShortcuts()
        }
    }

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "1":
                    selectedItem = .meetings
                    return nil
                case "2":
                    selectedItem = .recordings
                    return nil
                case "3":
                    selectedItem = .documents
                    return nil
                case "4":
                    selectedItem = .chat
                    return nil
                case "5":
                    selectedItem = .models
                    return nil
                case "6":
                    selectedItem = .settings
                    return nil
                case ",":
                    selectedItem = .settings
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }
}

#Preview {
    ContentView(selectedItem: .constant(.meetings))
}
