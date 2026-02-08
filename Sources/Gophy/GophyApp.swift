import SwiftUI

@main
struct GophyApp: App {
    @State private var navigationCoordinator = NavigationCoordinator()
    @State private var showOnboarding: Bool = !OnboardingViewModel.hasCompletedOnboarding()

    init() {
        // Install crash reporter as early as possible
        CrashReporter.shared.install()
        CrashReporter.shared.logInfo("GophyApp initializing")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(navigationCoordinator: navigationCoordinator)
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
                    navigationCoordinator.selectedItem = .meetings
                }
                .keyboardShortcut("n", modifiers: .command)
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
    @Bindable var navigationCoordinator: NavigationCoordinator
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedItem: $navigationCoordinator.selectedItem
            )
        } detail: {
            if let item = navigationCoordinator.selectedItem {
                PlaceholderView(
                    item: item,
                    selectedChatId: navigationCoordinator.selectedChatId
                )
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
        .environment(navigationCoordinator)
        .onAppear {
            setupKeyboardShortcuts()
        }
    }

    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "1":
                    navigationCoordinator.selectedItem = .meetings
                    return nil
                case "2":
                    navigationCoordinator.selectedItem = .documents
                    return nil
                case "3":
                    navigationCoordinator.selectedItem = .chat
                    return nil
                case "4":
                    navigationCoordinator.selectedItem = .models
                    return nil
                case "5":
                    navigationCoordinator.selectedItem = .settings
                    return nil
                case ",":
                    navigationCoordinator.selectedItem = .settings
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
    @Previewable @State var coordinator = NavigationCoordinator()
    ContentView(navigationCoordinator: coordinator)
}
