import SwiftUI
import SwiftData
import AppKit

enum AppTab: Hashable { case timer, stats, community }

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @AppStorage("timetableRailWidth") private var railWidth: Double = 320
    @State private var tab: AppTab = .timer

    // Left column is effectively fixed (~460pt); show the rail as soon as there's
    // room for the left column plus a minimal panel.
    private let leftMinWidth: CGFloat = 460
    private let railMinWidth: CGFloat = 260

    var body: some View {
        GeometryReader { geo in
            let hasRoom = geo.size.width >= leftMinWidth + railMinWidth
            let showRail = hasRoom && tab == .timer
            let maxRail = max(railMinWidth, geo.size.width - leftMinWidth)
            HStack(spacing: 0) {
                TabView(selection: $tab) {
                    Tab("Timer", systemImage: "timer", value: AppTab.timer) {
                        TimerView()
                    }
                    Tab("Stats", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                        StatsView()
                    }
                    Tab("Community", systemImage: "person.2", value: AppTab.community) {
                        CommunityView()
                    }
                }
                .frame(minWidth: leftMinWidth, maxWidth: .infinity)

                if showRail {
                    ResizableDivider(width: $railWidth, range: railMinWidth...maxRail)
                    TimetablePanel()
                        .frame(width: min(railWidth, maxRail))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showRail)
        }
        .frame(minWidth: 460, minHeight: 600)
        .task { seedDefaultCategoriesIfNeeded() }
    }

    private func seedDefaultCategoriesIfNeeded() {
        guard categories.isEmpty else { return }
        let defaults: [(String, String)] = [
            ("Deep Work", "#6366F1"),
            ("Study", "#10B981"),
            ("Admin", "#F59E0B"),
            ("Creative", "#EC4899"),
        ]
        for (index, (name, hex)) in defaults.enumerated() {
            context.insert(Category(name: name, colorHex: hex, sortOrder: index))
        }
        try? context.save()
    }
}

/// A 1pt divider with a wide invisible hit area that resizes the rail on drag.
private struct ResizableDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let base = startWidth ?? width
                                if startWidth == nil { startWidth = width }
                                // rail is on the right: dragging left widens it
                                width = min(range.upperBound, max(range.lowerBound, base - value.translation.width))
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            }
    }
}
