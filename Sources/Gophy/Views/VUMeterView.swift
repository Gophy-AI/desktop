import SwiftUI

@MainActor
struct VUMeterView: View {
    let level: Float
    let label: String

    private var normalizedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))

                    Rectangle()
                        .fill(levelColor)
                        .frame(width: geometry.size.width * normalizedLevel)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 12)

            Text(String(format: "%.0f%%", normalizedLevel * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private var levelColor: Color {
        if normalizedLevel > 0.9 {
            return .red
        } else if normalizedLevel > 0.7 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        VUMeterView(level: 0.3, label: "Microphone")
        VUMeterView(level: 0.7, label: "System Audio")
        VUMeterView(level: 0.95, label: "High Level")
    }
    .padding()
    .frame(width: 300)
}
