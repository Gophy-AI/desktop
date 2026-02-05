import SwiftUI

@MainActor
struct MeetingControlBar: View {
    let status: MeetingStatus
    let micLevel: Float
    let systemAudioLevel: Float
    let onStart: () async -> Void
    let onStop: () async -> Void
    let onPause: () async -> Void
    let onResume: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 16) {
                VStack(spacing: 8) {
                    VUMeterView(level: micLevel, label: "Microphone")
                    VUMeterView(level: systemAudioLevel, label: "System Audio")
                }
                .frame(maxWidth: .infinity)

                Spacer()

                HStack(spacing: 12) {
                    if status == .idle || status == .completed {
                        Button(action: {
                            Task {
                                await onStart()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                Text("Start")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else if status == .active {
                        Button(action: {
                            Task {
                                await onPause()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.title3)
                                Text("Pause")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(action: {
                            Task {
                                await onStop()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title3)
                                Text("Stop")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                    } else if status == .paused {
                        Button(action: {
                            Task {
                                await onResume()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                Text("Resume")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(action: {
                            Task {
                                await onStop()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title3)
                                Text("Stop")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.large)
                    } else if status == .starting || status == .stopping {
                        SwiftUI.ProgressView()
                            .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    VStack(spacing: 20) {
        MeetingControlBar(
            status: .idle,
            micLevel: 0.3,
            systemAudioLevel: 0.5,
            onStart: {},
            onStop: {},
            onPause: {},
            onResume: {}
        )

        MeetingControlBar(
            status: .active,
            micLevel: 0.7,
            systemAudioLevel: 0.4,
            onStart: {},
            onStop: {},
            onPause: {},
            onResume: {}
        )

        MeetingControlBar(
            status: .paused,
            micLevel: 0.0,
            systemAudioLevel: 0.0,
            onStart: {},
            onStop: {},
            onPause: {},
            onResume: {}
        )
    }
    .frame(width: 600)
}
