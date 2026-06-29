import SwiftUI
import SwiftData
import AppKit

/// Right-rail day timetable. Lays out finished sessions as schedule blocks for a
/// chosen day; overlapping blocks split into side-by-side columns. Tap a block to
/// edit it, or tap an empty slot to add a session at that time.
struct TimetablePanel: View {
    @State private var day: Date = Calendar.current.startOfDay(for: Date())

    private var isToday: Bool {
        Calendar.current.isDate(day, inSameDayAs: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TimetableDay(day: day).id(day)
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
}

private struct TimetableDay: View {
    let day: Date
    @Environment(\.modelContext) private var context
    @Query private var sessions: [FocusSession]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var editing: FocusSession?

    private let hourHeight: CGFloat = 58
    private let gutter: CGFloat = 50
    private let blockSpacing: CGFloat = 3
    private var ptPerMinute: CGFloat { hourHeight / 60 }

    init(day: Date) {
        self.day = day
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        _sessions = Query(
            filter: #Predicate<FocusSession> { s in
                s.endedAt != nil && s.startedAt >= start && s.startedAt < end
            },
            sort: \.startedAt
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in addSession(atY: value.location.y) }
                            )
                        hourGrid.allowsHitTesting(false)
                        ForEach(layout(width: geo.size.width), id: \.session.id) { item in
                            SessionBlockView(
                                session: item.session,
                                rect: item.rect,
                                ptPerMinute: ptPerMinute,
                                day: day,
                                selected: editing?.id == item.session.id,
                                onTap: { editing = item.session }
                            )
                        }
                        if Calendar.current.isDateInToday(day) {
                            nowLine.allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: hourHeight * 24)
                .padding(.vertical, 6)
                .removeScrollers()
            }
            .scrollIndicators(.hidden)
            .overlay {
                if sessions.isEmpty {
                    VStack(spacing: 4) {
                        Text("No sessions").font(.callout).foregroundStyle(.tertiary)
                        Text("Tap a slot to add one").font(.caption2).foregroundStyle(.quaternary)
                    }
                }
            }
            .task { scrollToFocus(proxy) }
        }
        .sheet(item: $editing) { session in
            BlockEditor(session: session) { editing = nil }
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

    private func layout(width: CGFloat) -> [(session: FocusSession, rect: CGRect)] {
        let laneWidth = max(40, width - gutter - 10)
        let items = sessions
            .map { (session: $0, top: yOffset($0), bottom: yOffset($0) + blockHeight($0)) }
            .sorted { $0.top < $1.top }

        var result: [(session: FocusSession, rect: CGRect)] = []
        var i = 0
        while i < items.count {
            // Grow a cluster of visually overlapping blocks.
            var clusterBottom = items[i].bottom
            var cluster = [items[i]]
            var j = i + 1
            while j < items.count, items[j].top < clusterBottom - 0.5 {
                clusterBottom = max(clusterBottom, items[j].bottom)
                cluster.append(items[j])
                j += 1
            }

            // Greedy column assignment within the cluster.
            var columnBottoms: [CGFloat] = []
            var columnOf: [Int] = []
            for item in cluster {
                if let free = columnBottoms.firstIndex(where: { $0 <= item.top + 0.5 }) {
                    columnBottoms[free] = item.bottom
                    columnOf.append(free)
                } else {
                    columnBottoms.append(item.bottom)
                    columnOf.append(columnBottoms.count - 1)
                }
            }

            let cols = max(1, columnBottoms.count)
            let colWidth = (laneWidth - blockSpacing * CGFloat(cols - 1)) / CGFloat(cols)
            for (k, item) in cluster.enumerated() {
                let x = gutter + CGFloat(columnOf[k]) * (colWidth + blockSpacing)
                result.append((
                    item.session,
                    CGRect(x: x, y: item.top, width: colWidth, height: item.bottom - item.top)
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

    private func yOffset(_ session: FocusSession) -> CGFloat {
        minutesFromDayStart(session.startedAt) * ptPerMinute
    }

    private func blockHeight(_ session: FocusSession) -> CGFloat {
        max(22, CGFloat(session.elapsedSeconds) / 60 * ptPerMinute)
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

    // MARK: - Add session from an empty slot

    private func addSession(atY y: CGFloat) {
        let cal = Calendar.current
        let rawMinutes = Int(y / ptPerMinute)
        let snapped = max(0, min(24 * 60 - 25, (rawMinutes / 5) * 5))
        let start = cal.date(byAdding: .minute, value: snapped, to: cal.startOfDay(for: day)) ?? day
        let defaultMinutes = 25
        let session = FocusSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(defaultMinutes * 60)),
            plannedMinutes: defaultMinutes,
            elapsedSeconds: defaultMinutes * 60,
            outcome: .endedEarly,
            activity: nil
        )
        context.insert(session)
        try? context.save()
        editing = session
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
    }

    private func commitBottom(_ dy: CGFloat) {
        let maxElapsed = Int(dayEnd.timeIntervalSince(session.startedAt))
        let newElapsed = min(max(session.elapsedSeconds + snapSeconds(dy), minSeconds), maxElapsed)
        session.elapsedSeconds = newElapsed
        session.endedAt = session.startedAt.addingTimeInterval(Double(newElapsed))
        try? context.save()
    }
}

// MARK: - Block editor

private struct BlockEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: FocusSession
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var activities: [Activity]
    var onClose: () -> Void

    @State private var title: String = ""
    @State private var startTime: Date = .now
    @State private var endTime: Date = .now
    @State private var categoryID: PersistentIdentifier?
    @State private var rating: FocusRating = .neutral
    @State private var note: String = ""

    private var durationSeconds: Int { max(0, Int(endTime.timeIntervalSince(startTime))) }

    private var activeCategories: [Category] { categories.filter { !$0.isArchived } }
    private var selectedCategory: Category? {
        categories.first { $0.id == categoryID } ?? session.activity?.category
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit session").font(.headline)

            field("Task") {
                TextField("Task title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            field("Category") {
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
            DatePicker("End", selection: $endTime, in: startTime..., displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)

            HStack {
                Text("Duration").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(durationSeconds > 0 ? formatDurationShort(seconds: durationSeconds) : "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(durationSeconds > 0 ? .primary : .secondary)
            }

            field("Focus") {
                Picker("Focus", selection: $rating) {
                    ForEach(FocusRating.allCases) { r in
                        Text("\(r.emoji)").tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            field("Note") {
                TextField("Note", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }

            Divider()

            HStack {
                Button(role: .destructive) { deleteSession() } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Done") { commit() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: selectedCategory?.colorHex ?? "#6366F1"))
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            title = session.activity?.name ?? ""
            startTime = session.startedAt
            endTime = session.endedAt ?? session.startedAt.addingTimeInterval(Double(max(session.elapsedSeconds, 300)))
            categoryID = session.activity?.category?.id ?? activeCategories.first?.id
            rating = session.rating
            note = session.note
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func commit() {
        let newName = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reassignActivity(to: newName.isEmpty ? "Untitled" : newName, category: selectedCategory)
        let safeEnd = max(endTime, startTime.addingTimeInterval(60))
        session.startedAt = startTime
        session.endedAt = safeEnd
        session.elapsedSeconds = Int(safeEnd.timeIntervalSince(startTime))
        session.rating = rating
        session.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        onClose()
    }

    /// Re-points this session to an Activity matching (name, category), creating
    /// one if needed, and deletes the previous Activity if left orphaned.
    private func reassignActivity(to name: String, category: Category?) {
        let old = session.activity
        if old?.name == name && old?.category?.id == category?.id { return }

        let target = activities.first { $0.name == name && $0.category?.id == category?.id }
            ?? {
                let created = Activity(name: name, category: category)
                context.insert(created)
                return created
            }()

        session.activity = target
        cleanupOrphan(old)
    }

    private func deleteSession() {
        let old = session.activity
        context.delete(session)
        cleanupOrphan(old)
        try? context.save()
        onClose()
    }

    private func cleanupOrphan(_ activity: Activity?) {
        guard let activity else { return }
        let remaining = activity.sessions.filter { $0.persistentModelID != session.persistentModelID }
        if remaining.isEmpty { context.delete(activity) }
    }
}
