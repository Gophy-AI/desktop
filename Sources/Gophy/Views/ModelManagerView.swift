import SwiftUI

@MainActor
struct ModelManagerView: View {
    @State private var viewModel = ModelManagerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.hasDownloadedModels {
                FirstLaunchBanner()
                    .padding()
            }

            DiskUsageSummary(totalDiskUsageGB: viewModel.totalDiskUsageGB)
                .padding(.horizontal)
                .padding(.vertical, 12)

            Divider()

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding()
            }

            List {
                ForEach(viewModel.models) { model in
                    ModelRow(
                        model: model,
                        isDownloaded: viewModel.isDownloaded(model),
                        isDownloading: viewModel.isDownloading(model),
                        progress: viewModel.downloadProgress[model.id],
                        onDownload: { viewModel.downloadModel(model) },
                        onCancel: { viewModel.cancelDownload(model) },
                        onDelete: { viewModel.deleteModel(model) }
                    )
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Models")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FirstLaunchBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Download models to get started")
                    .font(.headline)

                Text("Select models below to enable transcription, chat, and document analysis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DiskUsageSummary: View {
    let totalDiskUsageGB: Double

    var body: some View {
        HStack {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(.secondary)

            Text("Disk Usage:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(format: "%.2f GB", totalDiskUsageGB))
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ModelRow: View {
    let model: ModelDefinition
    let isDownloaded: Bool
    let isDownloading: Bool
    let progress: DownloadProgress?
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: modelIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(modelIconColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.name)
                            .font(.headline)

                        Spacer()

                        StatusBadge(
                            isDownloaded: isDownloaded,
                            isDownloading: isDownloading
                        )
                    }

                    HStack {
                        Text(model.type.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(String(format: "%.1f GB", model.approximateSizeGB))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                ActionButton(
                    isDownloaded: isDownloaded,
                    isDownloading: isDownloading,
                    onDownload: onDownload,
                    onCancel: onCancel,
                    onDelete: onDelete
                )
            }

            if isDownloading, let progress = progress {
                ProgressView(
                    model: model,
                    progress: progress
                )
            }
        }
        .padding(.vertical, 8)
    }

    private var modelIcon: String {
        switch model.type {
        case .stt:
            return "mic.fill"
        case .textGen:
            return "text.bubble"
        case .ocr:
            return "doc.viewfinder"
        case .embedding:
            return "circle.grid.3x3"
        }
    }

    private var modelIconColor: Color {
        switch model.type {
        case .stt:
            return .blue
        case .textGen:
            return .green
        case .ocr:
            return .orange
        case .embedding:
            return .purple
        }
    }
}

struct StatusBadge: View {
    let isDownloaded: Bool
    let isDownloading: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)

            Text(badgeText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.15))
        .cornerRadius(4)
    }

    private var badgeText: String {
        if isDownloaded {
            return "Ready"
        } else if isDownloading {
            return "Downloading"
        } else {
            return "Not Downloaded"
        }
    }

    private var badgeColor: Color {
        if isDownloaded {
            return .green
        } else if isDownloading {
            return .blue
        } else {
            return .gray
        }
    }
}

struct ActionButton: View {
    let isDownloaded: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if isDownloading {
            Button(action: onCancel) {
                Text("Cancel")
                    .frame(width: 80)
            }
            .buttonStyle(.bordered)
        } else if isDownloaded {
            Button(action: onDelete) {
                Text("Delete")
                    .frame(width: 80)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
        } else {
            Button(action: onDownload) {
                Text("Download")
                    .frame(width: 80)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ProgressView: View {
    let model: ModelDefinition
    let progress: DownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwiftUI.ProgressView(value: progress.fractionCompleted) {
                HStack {
                    Text(String(format: "%.0f%%", progress.fractionCompleted * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if progress.totalBytes > 0 {
                        Text("\(formattedBytes(progress.bytesDownloaded)) / \(formattedBytes(progress.totalBytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .progressViewStyle(.linear)

            if let speed = calculateSpeed() {
                Text(speed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calculateSpeed() -> String? {
        guard progress.totalBytes > 0,
              progress.bytesDownloaded > 0,
              case .downloading = progress.status else {
            return nil
        }

        let bytesPerSecond = Double(progress.bytesDownloaded) / 1.0
        return "\(formattedBytes(Int64(bytesPerSecond)))/s"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

extension ModelType {
    var displayName: String {
        switch self {
        case .stt:
            return "Speech-to-Text"
        case .textGen:
            return "Text Generation"
        case .ocr:
            return "OCR & Vision"
        case .embedding:
            return "Embeddings"
        }
    }
}

#Preview {
    ModelManagerView()
}
