import SwiftUI

/// A clock-style radial dial for setting the focus duration. Drag to spin the
/// minute hand; one revolution is 60 minutes, and you can wind past the top to
/// go over an hour (or below it for short sessions). The hub shows the total.
struct CircularDurationPicker: View {
    @Binding var minutes: Int
    var accent: Color
    var range: ClosedRange<Int> = 1...180

    private let size: CGFloat = 260
    private let fullCircleMinutes = 60

    // Drag state for delta-accumulated, multi-revolution winding.
    @State private var lastAngle: Double?
    @State private var accumulated: Double = 0

    private var clamped: Int { max(0, minutes) }
    private var revolutions: Int { clamped / fullCircleMinutes }
    private var remainder: Int { clamped % fullCircleMinutes }

    /// Fraction of the current revolution the hand has swept (0...1).
    private var fraction: Double {
        if clamped >= fullCircleMinutes && remainder == 0 { return 1 }
        return Double(remainder) / Double(fullCircleMinutes)
    }

    private var discDiameter: CGFloat { size * 0.66 }
    private var handLength: CGFloat { size * 0.43 }      // pokes out past the disc like a minute hand
    private var baseDiscOpacity: Double { revolutions >= 1 ? 0.30 : 0.12 }

    var body: some View {
        ZStack {
            ticks

            Circle()
                .fill(accent.opacity(baseDiscOpacity))
                .frame(width: discDiameter, height: discDiameter)

            PieSector(fraction: fraction)
                .fill(
                    AngularGradient(
                        colors: [accent.opacity(0.30), accent.opacity(0.85)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + fraction * 360)
                    )
                )
                .frame(width: discDiameter, height: discDiameter)

            hand
            hub
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { wind(to: $0.location) }
                .onEnded { _ in lastAngle = nil }
        )
    }

    private var ticks: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { i in
                let major = i % 5 == 0
                Capsule()
                    .fill(Color.primary.opacity(major ? 0.45 : 0.16))
                    .frame(width: major ? 2.5 : 1.5, height: major ? 12 : 7)
                    .offset(y: -size / 2 + (major ? 8 : 10))
                    .rotationEffect(.degrees(Double(i) / 60 * 360))
            }
        }
        .frame(width: size, height: size)
    }

    private var hand: some View {
        let tail: CGFloat = 18   // small counterweight past the center, like a real hand
        return ZStack {
            Capsule()
                .fill(accent)
                .frame(width: 6, height: handLength + tail)
                .offset(y: -(handLength - tail) / 2)
            Circle()
                .fill(accent)
                .frame(width: 15, height: 15)
                .offset(y: -handLength)
                .shadow(color: accent.opacity(0.45), radius: 7, y: 3)
        }
        .rotationEffect(.degrees(fraction * 360))
    }

    private var hub: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.14), radius: 9)
            VStack(spacing: -2) {
                Text(hubValue)
                    .font(.system(size: clamped >= 60 ? 32 : 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                Text(clamped >= 60 ? "hr" : "min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hubValue: String {
        if clamped >= 60 {
            return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
        }
        return "\(clamped)"
    }

    private func wind(to location: CGPoint) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        guard dx != 0 || dy != 0 else { return }

        let angle = atan2(dx, -dy)   // radians, 0 at top (12 o'clock), clockwise positive

        guard let last = lastAngle else {
            lastAngle = angle
            accumulated = Double(minutes)
            return
        }

        var delta = angle - last
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        accumulated += delta / (2 * .pi) * Double(fullCircleMinutes)
        accumulated = min(Double(range.upperBound), max(Double(range.lowerBound), accumulated))
        lastAngle = angle

        let value = Int(accumulated.rounded())
        if value != minutes { minutes = value }
    }
}

/// A filled pie sector starting at 12 o'clock, sweeping clockwise by `fraction`.
struct PieSector: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + fraction * 360),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
