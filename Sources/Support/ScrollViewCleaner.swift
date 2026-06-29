import SwiftUI
import AppKit

/// Reaches the backing NSScrollView and removes its scrollers outright.
/// SwiftUI's `.scrollIndicators(.hidden)` does not hide the persistent scroller
/// when a mouse is connected, so we strip it directly — retrying a few times
/// because the enclosing scroll view isn't available on the first layout pass.
private struct ScrollViewCleaner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        func attach(to view: NSView) {
            for delay in [0.0, 0.05, 0.2, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let scrollView = view.enclosingScrollView else { return }
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                    scrollView.verticalScroller?.alphaValue = 0
                    scrollView.horizontalScroller?.alphaValue = 0
                    scrollView.autohidesScrollers = true
                }
            }
        }
    }
}

extension View {
    /// Place inside a ScrollView's content to fully remove its scrollers.
    func removeScrollers() -> some View {
        background(ScrollViewCleaner().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
