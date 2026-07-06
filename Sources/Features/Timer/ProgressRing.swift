import SwiftUI

/// Calm monochrome progress ring. The track is a faint neutral; the accent
/// (later a category color) sweeps as focus progresses. In overtime the ring
/// is full and gently pulses.
struct ProgressRing: View {
    var progress: Double          // 0...1
    var accent: Color
    var isOvertime: Bool
    var label: String             // mm:ss / +mm:ss
    var caption: String           // task name or status

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.0001, progress))
                .stroke(accent.opacity(isOvertime ? 0.9 : 1),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
                .opacity(isOvertime && pulse ? 0.55 : 1)
                .animation(isOvertime ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default,
                           value: pulse)

            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                if isOvertime {
                    Text("OVERTIME")
                        .font(.caption2.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(accent)
                }
                if !caption.isEmpty {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                }
            }
        }
        .onAppear { pulse = isOvertime }
        .onChange(of: isOvertime) { _, now in pulse = now }
    }
}
