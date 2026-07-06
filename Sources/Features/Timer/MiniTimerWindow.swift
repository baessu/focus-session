import SwiftUI
import AppKit

/// Manages a small translucent always-on-top panel that shows just the running
/// timer. Two shapes: a compact square (ring with time inside) or a wide bar.
@MainActor
final class MiniTimerController {
    static let shared = MiniTimerController()

    private var panel: NSPanel?
    private weak var mainWindow: NSWindow?

    private static let compactSize = NSSize(width: 116, height: 128)
    private static let barSize = NSSize(width: 210, height: 74)

    init() {
        UserDefaults.standard.register(defaults: ["miniCompact": true])
    }

    private var isCompact: Bool { UserDefaults.standard.bool(forKey: "miniCompact") }
    private var size: NSSize { isCompact ? Self.compactSize : Self.barSize }

    /// Hide the main window and float the mini timer above everything.
    func minimize() {
        mainWindow = NSApp.windows.first {
            $0.isVisible && !($0 is NSPanel) && $0.contentView != nil
        }
        showPanel()
        mainWindow?.orderOut(nil)
    }

    /// Bring the main window back and hide the mini timer.
    func restore() {
        panel?.orderOut(nil)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Switch between the compact square and the wide bar shape.
    func toggleShape() {
        UserDefaults.standard.set(!isCompact, forKey: "miniCompact")
        resizeKeepingTopRight(to: size)
    }

    private func showPanel() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.alphaValue = 0.9
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: MiniTimerView())
            if let screen = NSScreen.main {
                let vf = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 20, y: vf.maxY - size.height - 20))
            }
            panel = p
        } else {
            resizeKeepingTopRight(to: size)
        }
        panel?.orderFrontRegardless()
    }

    private func resizeKeepingTopRight(to newSize: NSSize) {
        guard let panel else { return }
        var frame = panel.frame
        let topRight = NSPoint(x: frame.maxX, y: frame.maxY)   // keep the top-right corner fixed
        frame.size = newSize
        frame.origin = NSPoint(x: topRight.x - newSize.width, y: topRight.y - newSize.height)
        panel.setFrame(frame, display: true, animate: true)
    }
}

private struct MiniTimerView: View {
    @State private var engine = FocusTimerEngine.shared
    @AppStorage("timerShowsRemaining") private var showsRemaining = true
    @AppStorage("miniAccentHex") private var accentHex = "#6366F1"
    @AppStorage("miniCompact") private var compact = true

    private var accent: Color { Color(hex: accentHex) }

    var body: some View {
        Group {
            if compact { compactBody } else { barBody }
        }
        .background(.ultraThinMaterial, in: .rect(cornerRadius: compact ? 16 : 14))
        .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 14).stroke(.white.opacity(0.14)))
        .opacity(engine.phase == .paused ? 0.72 : 1)
        .onChange(of: engine.phase) { _, phase in
            if phase == .idle { MiniTimerController.shared.restore() }
        }
    }

    // MARK: layouts

    private var compactBody: some View {
        VStack(spacing: 7) {
            ringView(size: 86, showText: true)
            HStack(spacing: 14) { modeButton; shapeButton; restoreButton }
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .frame(width: 116, height: 128)
    }

    private var barBody: some View {
        HStack(spacing: 11) {
            ringView(size: 44, showText: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(timeText)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            VStack(spacing: 5) { modeButton; shapeButton; restoreButton }
                .font(.system(size: 11))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(width: 210, height: 74)
    }

    // MARK: pieces

    private func ringView(size: CGFloat, showText: Bool) -> some View {
        let lineWidth: CGFloat = size > 60 ? 5 : 4
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.13), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: ringFraction)
            if showText {
                VStack(spacing: 1) {
                    Text(timeText)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .offset(y: 2)
            }
        }
        .frame(width: size, height: size)
    }

    private var modeButton: some View {
        Button { showsRemaining.toggle() } label: { Image(systemName: "arrow.left.arrow.right") }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Switch elapsed / remaining")
    }

    private var shapeButton: some View {
        Button { MiniTimerController.shared.toggleShape() } label: {
            Image(systemName: compact ? "rectangle" : "square")
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help("Switch shape")
    }

    private var restoreButton: some View {
        Button { MiniTimerController.shared.restore() } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help("Restore window")
    }

    private var label: String {
        engine.phase == .paused ? "paused" : (showsRemaining ? "left" : "elapsed")
    }

    /// Remaining mode → drains toward empty; elapsed mode → fills up.
    private var ringFraction: CGFloat {
        if showsRemaining {
            return CGFloat(max(0, 1 - engine.progress))
        } else {
            return CGFloat(engine.isOvertime ? 1 : max(0.0001, engine.progress))
        }
    }

    private var timeText: String {
        showsRemaining ? engine.displayTime : formatClock(engine.elapsed)
    }
}
