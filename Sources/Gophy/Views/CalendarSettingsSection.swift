import SwiftUI
import EventKit

@MainActor
struct CalendarSettingsSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar")
                .font(.headline)

            Divider()

            googleAccountSection

            Divider()

            autoStartSection

            Divider()

            syncSection

            Divider()

            writebackSection

            Divider()

            eventKitSection
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Google Account

    @State private var clientIDInput: String = ""
    @State private var hasInitializedClientID = false

    private var googleAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google Account")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("OAuth Client ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Google OAuth Client ID", text: $clientIDInput)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            if !hasInitializedClientID {
                                clientIDInput = viewModel.googleClientID
                                hasInitializedClientID = true
                            }
                        }
                        .onSubmit {
                            viewModel.updateGoogleClientID(clientIDInput)
                        }

                    Button("Save") {
                        viewModel.updateGoogleClientID(clientIDInput)
                    }
                    .buttonStyle(.bordered)
                }

                Text("Create an OAuth 2.0 Client ID in the Google Cloud Console with Desktop app type")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isGoogleSignedIn ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    if viewModel.isGoogleSignedIn {
                        Text(viewModel.googleUserEmail ?? "Connected")
                            .font(.subheadline)
                    } else {
                        Text("Not connected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if viewModel.isGoogleSignedIn {
                    Button("Sign Out") {
                        viewModel.signOutGoogle()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Sign In with Google") {
                        Task {
                            await viewModel.signInGoogle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSigningIn || viewModel.googleClientID.isEmpty)
                }
            }

            if let error = viewModel.calendarErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Auto-Start

    private var autoStartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto-Start Recording", isOn: $viewModel.calendarAutoStartEnabled)
                .onChange(of: viewModel.calendarAutoStartEnabled) { _, newValue in
                    viewModel.updateCalendarAutoStart(newValue)
                }

            Text("Automatically start recording when a scheduled meeting begins")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.calendarAutoStartEnabled {
                Toggle("Only for meetings with video links", isOn: $viewModel.calendarAutoStartOnlyVideo)
                    .onChange(of: viewModel.calendarAutoStartOnlyVideo) { _, newValue in
                        viewModel.updateCalendarAutoStartOnlyVideo(newValue)
                    }
                    .padding(.leading, 20)

                HStack {
                    Text("Lead time")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: $viewModel.calendarAutoStartLeadTime) {
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                    .onChange(of: viewModel.calendarAutoStartLeadTime) { _, newValue in
                        viewModel.updateCalendarAutoStartLeadTime(newValue)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sync Interval")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $viewModel.calendarSyncInterval) {
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                    Text("30 minutes").tag(1800.0)
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .onChange(of: viewModel.calendarSyncInterval) { _, newValue in
                    viewModel.updateCalendarSyncInterval(newValue)
                }
            }

            HStack {
                if let lastSync = viewModel.lastCalendarSyncTime {
                    Text("Last synced: \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Sync Now") {
                    Task {
                        await viewModel.syncCalendarNow()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSyncingCalendar)
            }
        }
    }

    // MARK: - Writeback

    private var writebackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Write Meeting Summary to Calendar", isOn: $viewModel.calendarWritebackEnabled)
                .onChange(of: viewModel.calendarWritebackEnabled) { _, newValue in
                    viewModel.updateCalendarWriteback(newValue)
                }

            Text("After a meeting ends, append an AI-generated summary to the Google Calendar event description")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - EventKit

    private var eventKitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Calendars (EventKit)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.eventKitAccessGranted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(viewModel.eventKitAccessGranted ? "Access Granted" : "Access Not Granted")
                        .font(.subheadline)
                }

                Spacer()

                if !viewModel.eventKitAccessGranted {
                    Button("Grant Access") {
                        Task {
                            await viewModel.requestEventKitAccess()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.eventKitAccessGranted {
                Text("Local calendar events are merged with Google Calendar events for a unified view")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
