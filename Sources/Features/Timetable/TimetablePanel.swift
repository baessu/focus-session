import SwiftUI
import SwiftData
import AppKit

/// Right-rail day timetable. Lays out finished sessions as schedule blocks for a
/// chosen day; overlapping blocks split into side-by-side columns. Tap a block to
/// edit it, tap an empty slot to add a default session, or drag across empty space
/// to add one spanning exactly that time range.
struct TimetablePanel: View {
    @State private var day: Date = Calendar.current.startOfDay(for: Date())
    @State private var pendingNow = false

    private var isToday: Bool {
        Calendar.current.isDate(day, inSameDayAs: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TimetableDay(day: day, pendingNow: $pendingNow).id(day)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 1) {
                Text(day.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline.weight(.semibold))
                Text(day.formatted(.dateTime.month().day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { jumpToNow() } label: { Image(systemName: "scope") }
                .buttonStyle(.borderless)
                .help("Jump to now")

            if !isToday {
                Button("Today") { day = Calendar.current.startOfDay(for: Date()) }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
            }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func shift(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: day) {
            day = d
        }
    }

    /// Switch to today (if needed) and scroll the timetable to the current time.
    private func jumpToNow() {
        let today = Calendar.current.startOfDay(for: Date())
        if day != today { day = today }
        pendingNow = true
    }
}

private struct TimetableDay: View {
    let day: Date
    @Environment(\.modelContext) private var context
    @Query private var sessions: [FocusSession]
    @Query private var scheduleBlocks: [ScheduleBlock]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Binding var pendingNow: Bool
    @State private var editing: EditorTarget?
    @State private var dragStartY: CGFloat?
    @State private var dragCurrentY: CGFloat?
    @State private var engine = FocusTimerEngine.shared

    private let hourHeight: CGFloat = 58
    private let gutter: CGFloat = 50
    private let blockSpacing: CGFloat = 3
    private var ptPerMinute: CGFloat { hourHeight / 60 }

    init(day: Date, pendingNow: Binding<Bool>) {
        self.day = day
        self._pendingNow = pendingNow
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        _sessions = Query(
            filter: #Predicate<FocusSession> { s in
                s.endedAt != nil && s.startedAt >= start && s.startedAt < end
            },
            sort: \.startedAt
        )
        _scheduleBlocks = Query(
            filter: #Predicate<ScheduleBlock> { b in
                b.startedAt >= start && b.startedAt < end
            },
            sort: \.startedAt
        )
    }

    /// Focus sessions and schedule blocks unified for layout & rendering.
    private var items: [TimetableItem] {
        let focus = sessions.map {
            TimetableItem(id: "f-\($0.persistentModelID)", startedAt: $0.startedAt, seconds: $0.elapsedSeconds,
                          isSchedule: false, focus: $0, schedule: nil)
        }
        let schedule = scheduleBlocks.map {
            TimetableItem(id: "s-\($0.persistentModelID)", startedAt: $0.startedAt, seconds: $0.durationSeconds,
                          isSchedule: true, focus: nil, schedule: $0)
        }
        return focus + schedule
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(createGesture)
                        hourGrid.allowsHitTesting(false)
                        if let draft {
                            draftBlock(draft, width: geo.size.width).allowsHitTesting(false)
                        }
                        ForEach(layout(width: geo.size.width), id: \.item.id) { entry in
                            if let session = entry.item.focus {
                                SessionBlockView(
                                    session: session,
                                    rect: entry.rect,
                                    ptPerMinute: ptPerMinute,
                                    day: day,
                                    selected: editing?.id == entry.item.id,
                                    onTap: { editing = .focus(session) }
                                )
                            } else if let block = entry.item.schedule {
                                ScheduleBlockView(
                                    block: block,
                                    rect: entry.rect,
                                    selected: editing?.id == entry.item.id,
                                    onTap: { editing = .schedule(block) }
                                )
                            }
                        }
                        if Calendar.current.isDateInToday(day),
                           engine.phase != .idle,
                           let start = engine.startedAt,
                           Calendar.current.isDateInToday(start) {
                            liveBlock(start: start, width: geo.size.width).allowsHitTesting(false)
                        }
                        if Calendar.current.isDateInToday(day) {
                            nowLine.allowsHitTesting(false)
                        }
                    }
                    .coordinateSpace(.named("grid"))
                }
                .frame(height: hourHeight * 24)
                .padding(.vertical, 6)
                .removeScrollers()
            }
            .scrollIndicators(.hidden)
            .overlay {
                if sessions.isEmpty && scheduleBlocks.isEmpty {
                    VStack(spacing: 4) {
                        Text("Nothing yet").font(.callout).foregroundStyle(.tertiary)
                        Text("Tap or drag to add a block").font(.caption2).foregroundStyle(.quaternary)
                    }
                }
            }
            .task {
                if pendingNow {
                    scrollToNow(proxy)
                    pendingNow = false
                } else {
                    scrollToFocus(proxy)
                }
            }
            .onChange(of: pendingNow) { _, requested in
                if requested {
                    scrollToNow(proxy)
                    pendingNow = false
                }
            }
        }
        .sheet(item: $editing) { target in
            BlockEditor(target: target) { editing = nil }
        }
    }

    private var nowLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let mins = minutesFromDayStart(context.date)
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .offset(x: 44, y: mins * ptPerMinute - 3)
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                        .offset(y: -5)
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    // MARK: - Column layout for overlapping blocks

    private func layout(width: CGFloat) -> [(item: TimetableItem, rect: CGRect)] {
        let laneWidth = max(40, width - gutter - 10)
        let placed = items
            .map { (item: $0, top: yOffset($0.startedAt), bottom: yOffset($0.startedAt) + blockHeight($0.seconds)) }
            .sorted { $0.top < $1.top }

        var result: [(item: TimetableItem, rect: CGRect)] = []
        var i = 0
        while i < placed.count {
            // Grow a cluster of visually overlapping blocks.
            var clusterBottom = placed[i].bottom
            var cluster = [placed[i]]
            var j = i + 1
            while j < placed.count, placed[j].top < clusterBottom - 0.5 {
                clusterBottom = max(clusterBottom, placed[j].bottom)
                cluster.append(placed[j])
                j += 1
            }

            // Greedy column assignment within the cluster.
            var columnBottoms: [CGFloat] = []
            var columnOf: [Int] = []
            for entry in cluster {
                if let free = columnBottoms.firstIndex(where: { $0 <= entry.top + 0.5 }) {
                    columnBottoms[free] = entry.bottom
                    columnOf.append(free)
                } else {
                    columnBottoms.append(entry.bottom)
                    columnOf.append(columnBottoms.count - 1)
                }
            }

            let cols = max(1, columnBottoms.count)
            let colWidth = (laneWidth - blockSpacing * CGFloat(cols - 1)) / CGFloat(cols)
            for (k, entry) in cluster.enumerated() {
                let x = gutter + CGFloat(columnOf[k]) * (colWidth + blockSpacing)
                result.append((
                    entry.item,
                    CGRect(x: x, y: entry.top, width: colWidth, height: entry.bottom - entry.top)
                ))
            }
            i = j
        }
        return result
    }

    private func minutesFromDayStart(_ date: Date) -> CGFloat {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return CGFloat(c.hour ?? 0) * 60 + CGFloat(c.minute ?? 0) + CGFloat(c.second ?? 0) / 60
    }

    private func yOffset(_ date: Date) -> CGFloat {
        minutesFromDayStart(date) * ptPerMinute
    }

    private func blockHeight(_ seconds: Int) -> CGFloat {
        max(22, CGFloat(seconds) / 60 * ptPerMinute)
    }

    private func hourLabel(_ h: Int) -> String {
        let ampm = h < 12 ? "AM" : "PM"
        let hr = h % 12 == 0 ? 12 : h % 12
        return "\(hr) \(ampm)"
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        let hour = sessions.first.map { Calendar.current.component(.hour, from: $0.startedAt) } ?? 8
        proxy.scrollTo(max(0, hour - 1), anchor: .top)
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        let hour = Calendar.current.component(.hour, from: Date())
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(hour, anchor: .center)
        }
    }

    // MARK: - Create session (click = default length, drag = dragged length)

    /// One gesture handles both: a plain click (no drag) makes a default-length
    /// block; a drag makes a block spanning exactly the dragged range. Reported
    /// in the "grid" space so the created time lines up with the blocks.
    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
            .onChanged { value in
                if dragStartY == nil { dragStartY = value.startLocation.y }
                dragCurrentY = value.location.y
            }
            .onEnded { value in
                createSession(fromY: dragStartY ?? value.startLocation.y, toY: value.location.y)
                dragStartY = nil
                dragCurrentY = nil
            }
    }

    private func minutes(atY y: CGFloat) -> Double {
        Double(max(0, y)) / Double(ptPerMinute)
    }

    private func snap5(_ minutes: Double) -> Int {
        Int((minutes / 5).rounded()) * 5
    }

    private func createSession(fromY: CGFloat, toY: CGFloat) {
        let cal = Calendar.current
        let lowMinutes = minutes(atY: min(fromY, toY))
        let highMinutes = minutes(atY: max(fromY, toY))
        let span = highMinutes - lowMinutes
        // Treat a near-zero drag as a click → default 25-minute block.
        let duration = span < 3 ? 25 : max(5, snap5(span))
        let startMin = max(0, min(24 * 60 - duration, snap5(lowMinutes)))
        let start = cal.date(byAdding: .minute, value: startMin, to: cal.startOfDay(for: day)) ?? day
        let session = FocusSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(duration * 60)),
            plannedMinutes: duration,
            elapsedSeconds: duration * 60,
            outcome: .endedEarly,
            activity: nil
        )
        context.insert(session)
        try? context.save()
        editing = .focus(session)
    }

    // MARK: - Live drag preview

    private struct DraftBlock {
        let y: CGFloat
        let height: CGFloat
        let label: String
    }

    private var draft: DraftBlock? {
        guard let s = dragStartY, let c = dragCurrentY else { return nil }
        let lowMinutes = minutes(atY: min(s, c))
        let highMinutes = minutes(atY: max(s, c))
        guard highMinutes - lowMinutes >= 3 else { return nil }   // clicks don't preview
        let startMin = max(0, snap5(lowMinutes))
        let duration = max(5, snap5(highMinutes - lowMinutes))
        let cal = Calendar.current
        let start = cal.date(byAdding: .minute, value: startMin, to: cal.startOfDay(for: day)) ?? day
        let end = start.addingTimeInterval(Double(duration * 60))
        let label = "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
        return DraftBlock(y: CGFloat(startMin) * ptPerMinute, height: CGFloat(duration) * ptPerMinute, label: label)
    }

    /// The in-progress focus session, drawn live from the timer engine (start → now).
    private func liveBlock(start: Date, width: CGFloat) -> some View {
        let laneWidth = max(40, width - gutter - 10)
        return TimelineView(.periodic(from: .now, by: 15)) { context in
            let top = minutesFromDayStart(start) * ptPerMinute
            let bottom = minutesFromDayStart(context.date) * ptPerMinute
            let height = max(24, bottom - top)
            LiveBlockView(title: engine.taskName, paused: engine.phase == .paused)
                .frame(width: laneWidth, height: height, alignment: .top)
                .offset(x: gutter, y: top)
        }
    }

    private func draftBlock(_ draft: DraftBlock, width: CGFloat) -> some View {
        let laneWidth = max(40, width - gutter - 10)
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                Text(draft.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .lineLimit(1)
            }
            .frame(width: laneWidth, height: draft.height, alignment: .top)
            .offset(x: gutter, y: draft.y)
    }
}

// MARK: - Unified timetable item + editor target

/// A focus session or a schedule block, normalized for layout and rendering.
private struct TimetableItem: Identifiable {
    let id: String
    let startedAt: Date
    let seconds: Int
    let isSchedule: Bool
    let focus: FocusSession?
    let schedule: ScheduleBlock?
}

/// What the block editor is editing — used as the sheet item.
private enum EditorTarget: Identifiable {
    case focus(FocusSession)
    case schedule(ScheduleBlock)

    var id: String {
        switch self {
        case .focus(let s): return "f-\(s.persistentModelID)"
        case .schedule(let b): return "s-\(b.persistentModelID)"
        }
    }
}

// MARK: - Schedule block (outline, tap to edit)

private struct ScheduleBlockView: View {
    let block: ScheduleBlock
    let rect: CGRect
    let selected: Bool
    var onTap: () -> Void

    private var color: Color { Color(hex: block.colorHex) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9))
                        .foregroundStyle(color)
                    Text(block.title.isEmpty ? "Schedule" : block.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                if rect.height >= 34 {
                    Text(timeRange)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(width: rect.width, height: rect.height, alignment: .top)
        .background(color.opacity(0.06), in: .rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(color.opacity(selected ? 0.9 : 0.55),
                              style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: [4, 3]))
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .offset(x: rect.minX, y: rect.minY)
    }

    private var timeRange: String {
        "\(block.startedAt.formatted(date: .omitted, time: .shortened)) – \(block.endedAt.formatted(date: .omitted, time: .shortened))"
    }
}

/// The currently-running session, shown live on today's timetable.
private struct LiveBlockView: View {
    let title: String
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let color = Color.accentColor
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(paused ? Color.secondary : color)
                        .frame(width: 6, height: 6)
                        .opacity(!paused && pulse ? 0.3 : 1)
                    Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Focusing" : title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                Text(paused ? "Paused" : "In progress")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(color.opacity(0.16), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color, lineWidth: 1.5))
        .onAppear {
            if !paused && !reduceMotion {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}

private struct SessionBlock: View {
    let name: String
    let durationText: String
    let color: Color
    let selected: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if !compact {
                    Text(durationText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(color.opacity(0.16))
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? color : Color.clear, lineWidth: 2)
        )
    }
}

/// A session block that can be tapped (edit), dragged (move its time), or
/// resized from either edge (change start / end). Snaps to 5-minute steps.
private struct SessionBlockView: View {
    @Environment(\.modelContext) private var context
    let session: FocusSession
    let rect: CGRect
    let ptPerMinute: CGFloat
    let day: Date
    let selected: Bool
    var onTap: () -> Void

    enum Mode { case move, top, bottom }
    @State private var mode: Mode?
    @State private var moveDY: CGFloat = 0
    @State private var topDY: CGFloat = 0
    @State private var bottomDY: CGFloat = 0

    private let minSeconds = 300            // 5-minute floor
    private var canvasHeight: CGFloat { ptPerMinute * 60 * 24 }
    private var minHeight: CGFloat { CGFloat(minSeconds) / 60 * ptPerMinute }

    private var liveRect: CGRect {
        let y = rect.minY + moveDY + topDY
        let h = max(minHeight, rect.height - topDY + bottomDY)
        return CGRect(x: rect.minX, y: y, width: rect.width, height: h)
    }

    var body: some View {
        SessionBlock(
            name: session.activity?.name ?? "Untitled",
            durationText: formatDurationShort(seconds: session.elapsedSeconds),
            color: Color(hex: session.activity?.category?.colorHex ?? "#8E8E93"),
            selected: selected,
            compact: liveRect.height < 34
        )
        .frame(width: liveRect.width, height: liveRect.height, alignment: .top)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                switch zone(location.y, height: liveRect.height) {
                case .top, .bottom: NSCursor.resizeUpDown.set()
                case .move: NSCursor.arrow.set()
                }
            case .ended:
                NSCursor.arrow.set()
            }
        }
        // High priority so a block drag wins over the surrounding ScrollView
        // (otherwise the list scrolls at the same time → the block jitters).
        .highPriorityGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if mode == nil { mode = zone(value.startLocation.y, height: rect.height) }
                    switch mode {
                    case .move: moveDY = value.translation.height
                    case .top: topDY = clampedTop(value.translation.height)
                    case .bottom: bottomDY = clampedBottom(value.translation.height)
                    case .none: break
                    }
                }
                .onEnded { value in
                    switch mode {
                    case .move: commitMove(value.translation.height)
                    case .top: commitTop(value.translation.height)
                    case .bottom: commitBottom(value.translation.height)
                    case .none: break
                    }
                    mode = nil; moveDY = 0; topDY = 0; bottomDY = 0
                }
        )
        .onTapGesture { onTap() }
        .offset(x: liveRect.minX, y: liveRect.minY)
    }

    /// Which part of the block a point falls in. Edge bands scale with height so
    /// even short blocks remain resizable, while keeping a movable middle.
    private func zone(_ y: CGFloat, height: CGFloat) -> Mode {
        let band = min(12, height * 0.3)
        if y < band { return .top }
        if y > height - band { return .bottom }
        return .move
    }

    // MARK: live-drag clamps (in points)

    private func clampedTop(_ dy: CGFloat) -> CGFloat {
        min(max(dy, -rect.minY), rect.height - minHeight)
    }

    private func clampedBottom(_ dy: CGFloat) -> CGFloat {
        let maxGrow = canvasHeight - rect.minY - rect.height
        return min(max(dy, minHeight - rect.height), maxGrow)
    }

    // MARK: commits (snap to 5 min, mutate model, save)

    private func snapSeconds(_ dy: CGFloat) -> Int {
        let minutes = Int((dy / ptPerMinute / 5).rounded()) * 5
        return minutes * 60
    }

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }
    private var dayEnd: Date { dayStart.addingTimeInterval(24 * 3600) }

    private func commitMove(_ dy: CGFloat) {
        let elapsed = session.elapsedSeconds
        let maxStart = dayEnd.addingTimeInterval(-Double(elapsed))
        let newStart = min(max(session.startedAt.addingTimeInterval(Double(snapSeconds(dy))), dayStart), maxStart)
        session.startedAt = newStart
        session.endedAt = newStart.addingTimeInterval(Double(elapsed))
        try? context.save()
        publishSessionToCommunity(session, context: context)
    }

    private func commitTop(_ dy: CGFloat) {
        let end = session.startedAt.addingTimeInterval(Double(session.elapsedSeconds))
        var newStart = session.startedAt.addingTimeInterval(Double(snapSeconds(dy)))
        newStart = max(newStart, dayStart)
        newStart = min(newStart, end.addingTimeInterval(-Double(minSeconds)))
        session.startedAt = newStart
        session.elapsedSeconds = Int(end.timeIntervalSince(newStart))
        session.endedAt = end
        try? context.save()
        publishSessionToCommunity(session, context: context)
    }

    private func commitBottom(_ dy: CGFloat) {
        let maxElapsed = Int(dayEnd.timeIntervalSince(session.startedAt))
        let newElapsed = min(max(session.elapsedSeconds + snapSeconds(dy), minSeconds), maxElapsed)
        session.elapsedSeconds = newElapsed
        session.endedAt = session.startedAt.addingTimeInterval(Double(newElapsed))
        try? context.save()
        publishSessionToCommunity(session, context: context)
    }
}

// MARK: - Block editor (focus or schedule, with type toggle)

private enum BlockKind: Int, CaseIterable, Identifiable {
    case focus, schedule
    var id: Int { rawValue }
    var label: String { self == .focus ? "Focus" : "Schedule" }
}

private struct BlockEditor: View {
    @Environment(\.modelContext) private var context
    let target: EditorTarget
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var activities: [Activity]
    @Query private var scheduleBlocks: [ScheduleBlock]
    var onClose: () -> Void

    @State private var kind: BlockKind = .focus
    @State private var title: String = ""
    @State private var startTime: Date = .now
    @State private var endTime: Date = .now
    @State private var categoryID: PersistentIdentifier?
    @State private var rating: FocusRating = .neutral
    @State private var note: String = ""

    private var durationSeconds: Int { max(0, Int(endTime.timeIntervalSince(startTime))) }
    private var activeCategories: [Category] { categories.filter { !$0.isArchived } }
    private var selectedCategory: Category? { categories.first { $0.id == categoryID } }
    private var tint: Color { Color(hex: selectedCategory?.colorHex ?? "#6366F1") }

    private var taskSuggestions: [TaskSuggestion] {
        activities.filter { !$0.isArchived }.map {
            TaskSuggestion(name: $0.name, categoryID: $0.category?.id,
                           categoryName: $0.category?.name, colorHex: $0.category?.colorHex)
        }
    }

    /// Distinct prior schedule titles (most recent first), with their color and
    /// the matching category (if any) so selecting one restores it.
    private var scheduleSuggestions: [TaskSuggestion] {
        var seen = Set<String>()
        var result: [TaskSuggestion] = []
        for block in scheduleBlocks.sorted(by: { $0.startedAt > $1.startedAt }) {
            let title = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(title).inserted else { continue }
            let match = categories.first { $0.colorHex == block.colorHex }
            result.append(TaskSuggestion(name: title, categoryID: match?.id,
                                         categoryName: match?.name, colorHex: block.colorHex))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind == .focus ? "Edit focus" : "Edit schedule").font(.headline)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            Picker("Type", selection: $kind) {
                ForEach(BlockKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            field("Title") {
                SuggestingTextField(
                    text: $title,
                    placeholder: kind == .focus ? "Task title" : "e.g. Team meeting",
                    suggestions: kind == .focus ? taskSuggestions : scheduleSuggestions,
                    filled: true
                ) { picked in
                    if let cid = picked.categoryID { categoryID = cid }
                }
            }
            .zIndex(1)

            field(kind == .focus ? "Category" : "Color") {
                Menu {
                    ForEach(activeCategories) { category in
                        Button(category.name) { categoryID = category.id }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: selectedCategory?.colorHex ?? "#8E8E93"))
                            .frame(width: 10, height: 10)
                        Text(selectedCategory?.name ?? "Uncategorized")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                .menuStyle(.borderlessButton)
            }

            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
            // No `in: startTime...` range here: while `load()` populates a past
            // block, the picker's stale lower bound (initially .now) would clamp
            // the real end time up to now. `commit()` enforces end > start instead.
            DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)

            HStack {
                Text("Duration").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(durationSeconds > 0 ? formatDurationShort(seconds: durationSeconds) : "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(durationSeconds > 0 ? .primary : .secondary)
            }

            if kind == .focus {
                field("Focus") {
                    HStack(spacing: 8) {
                        ForEach(FocusRating.allCases) { r in
                            Button { rating = r } label: {
                                VStack(spacing: 5) {
                                    FocusBars(rating: r, maxHeight: 16)
                                    Text(r.label).font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(rating == r ? r.tint.opacity(0.16) : Color.primary.opacity(0.05),
                                            in: .rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(rating == r ? r.tint : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                field("Note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
                }
            } else {
                Text("Schedule blocks are shown on the timetable only — they don't count toward focus stats or the community.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button(role: .destructive) { delete() } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Done") { commit() }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: load)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: load / save

    private func load() {
        switch target {
        case .focus(let s):
            kind = .focus
            title = s.activity?.name ?? ""
            startTime = s.startedAt
            endTime = s.endedAt ?? s.startedAt.addingTimeInterval(Double(max(s.elapsedSeconds, 300)))
            categoryID = s.activity?.category?.id ?? activeCategories.first?.id
            rating = s.rating
            note = s.note
        case .schedule(let b):
            kind = .schedule
            title = b.title
            startTime = b.startedAt
            endTime = b.endedAt
            categoryID = categories.first { $0.colorHex == b.colorHex }?.id ?? activeCategories.first?.id
            rating = .neutral
            note = ""
        }
    }

    private func commit() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeEnd = max(endTime, startTime.addingTimeInterval(60))
        let seconds = Int(safeEnd.timeIntervalSince(startTime))
        let colorHex = selectedCategory?.colorHex ?? "#8E8E93"

        switch (target, kind) {
        case (.focus(let s), .focus):
            reassignActivity(s, to: cleanTitle.isEmpty ? "Untitled" : cleanTitle, category: selectedCategory)
            s.startedAt = startTime
            s.endedAt = safeEnd
            s.elapsedSeconds = seconds
            s.rating = rating
            s.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try? context.save()
            publishSessionToCommunity(s, context: context)

        case (.schedule(let b), .schedule):
            b.title = cleanTitle.isEmpty ? "Schedule" : cleanTitle
            b.startedAt = startTime
            b.endedAt = safeEnd
            b.colorHex = colorHex
            try? context.save()

        case (.focus(let s), .schedule):   // convert focus → schedule
            unpublishSessionFromCommunity(s)
            let old = s.activity
            context.delete(s)
            cleanupOrphan(old, excluding: s)
            context.insert(ScheduleBlock(title: cleanTitle.isEmpty ? "Schedule" : cleanTitle,
                                         startedAt: startTime, endedAt: safeEnd, colorHex: colorHex))
            try? context.save()

        case (.schedule(let b), .focus):   // convert schedule → focus
            context.delete(b)
            let activity = findOrCreateActivity(name: cleanTitle.isEmpty ? "Untitled" : cleanTitle, category: selectedCategory)
            let session = FocusSession(startedAt: startTime, endedAt: safeEnd,
                                       plannedMinutes: max(1, seconds / 60), elapsedSeconds: seconds,
                                       outcome: .endedEarly, activity: activity)
            session.rating = rating
            session.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(session)
            try? context.save()
            publishSessionToCommunity(session, context: context)
        }

        onClose()
    }

    private func delete() {
        switch target {
        case .focus(let s):
            unpublishSessionFromCommunity(s)
            let old = s.activity
            context.delete(s)
            cleanupOrphan(old, excluding: s)
        case .schedule(let b):
            context.delete(b)
        }
        try? context.save()
        onClose()
    }

    // MARK: activity helpers

    private func findOrCreateActivity(name: String, category: Category?) -> Activity {
        if let existing = activities.first(where: { $0.name == name && $0.category?.id == category?.id }) {
            return existing
        }
        let created = Activity(name: name, category: category)
        context.insert(created)
        return created
    }

    private func reassignActivity(_ session: FocusSession, to name: String, category: Category?) {
        let old = session.activity
        if old?.name == name && old?.category?.id == category?.id { return }
        session.activity = findOrCreateActivity(name: name, category: category)
        cleanupOrphan(old, excluding: session)
    }

    private func cleanupOrphan(_ activity: Activity?, excluding session: FocusSession) {
        guard let activity else { return }
        let remaining = activity.sessions.filter { $0.persistentModelID != session.persistentModelID }
        if remaining.isEmpty { context.delete(activity) }
    }
}
