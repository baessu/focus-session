import SwiftUI
import SwiftData

struct TimerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var activities: [Activity]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var recent: [FocusSession]

    @State private var engine = FocusTimerEngine.shared
    @State private var selectedCategoryID: PersistentIdentifier?
    @State private var pendingResult: SessionResult?
    private let notif = NotificationService.shared

    private var activeCategories: [Category] { categories.filter { !$0.isArchived } }

    private var selectedCategory: Category? {
        activeCategories.first { $0.id == selectedCategoryID } ?? activeCategories.first
    }

    private var accent: Color {
        Color(hex: selectedCategory?.colorHex ?? "#6366F1")
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            Group {
                if engine.phase == .idle {
                    ScrollView {
                        VStack(spacing: 28) {
                            SetupCard(
                                engine: engine,
                                accent: accent,
                                categories: activeCategories,
                                selectedCategoryID: $selectedCategoryID
                            )
                            if !completedRecent.isEmpty {
                                RecentSessionsList(sessions: completedRecent)
                            }
                        }
                        .padding(28)
                        .removeScrollers()
                    }
                    .scrollIndicators(.hidden)
                    .transition(.opacity)
                } else {
                    ActiveCard(engine: engine, accent: accent) { result in
                        if result.focusedSeconds > 0 { pendingResult = result }
                    }
                    .padding(28)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: engine.phase)
        }
        .sheet(item: $pendingResult) { result in
            SessionRatingSheet(result: result, accent: accent) { rating, note in
                persist(result, rating: rating, note: note)
                pendingResult = nil
            }
        }
        .onAppear {
            if selectedCategoryID == nil { selectedCategoryID = activeCategories.first?.id }
            engine.onPlannedReached = { SoundManager.playEnd() }
        }
        .onChange(of: engine.phase) { oldPhase, newPhase in
            switch newPhase {
            case .running:
                if oldPhase == .idle { SoundManager.playStart() }
                notif.requestAuthorizationIfNeeded()
                notif.scheduleCompletion(after: engine.remaining, taskName: engine.taskName)
            case .paused, .idle:
                notif.cancelCompletion()
            }
        }
    }

    private var completedRecent: [FocusSession] {
        Array(recent.filter { $0.endedAt != nil }.prefix(6))
    }

    private func persist(_ result: SessionResult, rating: FocusRating, note: String) {
        guard result.focusedSeconds > 0 else { return }
        let name = result.taskName.isEmpty ? "Untitled" : result.taskName
        let category = selectedCategory
        let activity = findOrCreateActivity(name: name, category: category)

        // Normalize implausibly long sessions (e.g. left running overnight).
        let cap = 16 * 3600
        var elapsed = result.focusedSeconds
        var endedAt = result.endedAt
        var autoNote = ""
        if elapsed > cap {
            autoNote = "Auto-capped from \(formatDurationShort(seconds: elapsed)) to 16h."
            elapsed = cap
            endedAt = result.startedAt.addingTimeInterval(Double(cap))
        }

        let session = FocusSession(
            startedAt: result.startedAt,
            endedAt: endedAt,
            plannedMinutes: result.plannedMinutes,
            elapsedSeconds: elapsed,
            outcome: result.reachedPlanned ? .completed : .endedEarly,
            activity: activity
        )
        session.rating = rating
        let userNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.note = [userNote, autoNote].filter { !$0.isEmpty }.joined(separator: "\n")
        context.insert(session)
        try? context.save()
    }

    private func findOrCreateActivity(name: String, category: Category?) -> Activity {
        if let existing = activities.first(where: {
            $0.name == name && $0.category?.id == category?.id
        }) {
            return existing
        }
        let activity = Activity(name: name, category: category)
        context.insert(activity)
        return activity
    }
}

// MARK: - Setup (idle)

private struct SetupCard: View {
    @Bindable var engine: FocusTimerEngine
    var accent: Color
    var categories: [Category]
    @Binding var selectedCategoryID: PersistentIdentifier?
    private let chips = [15, 25, 45, 60]

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("What will you focus on?")
                    .font(.title3.weight(.semibold))
                Text("Name it, pick a category, set a duration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !categories.isEmpty {
                CategoryPicker(categories: categories, selectedID: $selectedCategoryID)
            }

            TextField("e.g. Write the report", text: $engine.taskName)
                .textFieldStyle(.plain)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))

            VStack(spacing: 16) {
                CircularDurationPicker(minutes: $engine.plannedMinutes, accent: accent)

                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { value in
                        let selected = engine.plannedMinutes == value
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { engine.plannedMinutes = value }
                        } label: {
                            Text("\(value)m")
                                .font(.callout.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(selected ? accent : Color.primary.opacity(0.06),
                                            in: .rect(cornerRadius: 9))
                                .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button { engine.start() } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(!engine.canStart)
        }
        .frame(maxWidth: 380)
    }
}

private struct CategoryPicker: View {
    @Environment(\.modelContext) private var context
    var categories: [Category]
    @Binding var selectedID: PersistentIdentifier?
    @State private var showingAdd = false
    @State private var showingManager = false
    @State private var showingMenu = false

    private var selected: Category? {
        categories.first { $0.id == selectedID } ?? categories.first
    }

    var body: some View {
        Button { showingMenu.toggle() } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(Color(hex: selected?.colorHex ?? "#6366F1"))
                    .frame(width: 10, height: 10)
                Text(selected?.name ?? "Category")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingMenu, arrowEdge: .bottom) { menuList }
        .sheet(isPresented: $showingAdd) {
            AddCategorySheet(nextSortOrder: categories.count) { name, hex in
                let category = Category(name: name, colorHex: hex, sortOrder: categories.count)
                context.insert(category)
                try? context.save()
                selectedID = category.id
            }
        }
        .sheet(isPresented: $showingManager) { CategoryManagerSheet() }
    }

    private var menuList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(categories) { category in
                Button {
                    selectedID = category.id
                    showingMenu = false
                } label: {
                    HStack(spacing: 9) {
                        Circle().fill(Color(hex: category.colorHex)).frame(width: 10, height: 10)
                        Text(category.name)
                        Spacer(minLength: 12)
                        if category.id == selectedID {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        category.id == selectedID ? Color.primary.opacity(0.06) : .clear,
                        in: .rect(cornerRadius: 7)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { archive(category) } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
            }

            Divider().padding(.vertical, 4)

            Button {
                showingMenu = false
                showingAdd = true
            } label: {
                menuRowLabel("New category…", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                showingMenu = false
                showingManager = true
            } label: {
                menuRowLabel("Edit categories…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(width: 250)
    }

    private func menuRowLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage).frame(width: 10)
            Text(title)
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func archive(_ category: Category) {
        category.isArchived = true
        if selectedID == category.id {
            selectedID = categories.first { $0.id != category.id }?.id
        }
        try? context.save()
    }
}

private struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    var nextSortOrder: Int
    var onAdd: (String, String) -> Void

    @State private var name = ""
    @State private var hex = CategoryPalette.swatches[0]

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New category").font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 8), spacing: 12) {
                ForEach(CategoryPalette.swatches, id: \.self) { swatch in
                    Circle()
                        .fill(Color(hex: swatch))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(.primary, lineWidth: hex == swatch ? 2.5 : 0))
                        .onTapGesture { hex = swatch }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    guard !trimmed.isEmpty else { return }
                    onAdd(trimmed, hex)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: hex))
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

// MARK: - Active (running / paused)

private struct ActiveCard: View {
    @Bindable var engine: FocusTimerEngine
    var accent: Color
    var onEnd: (SessionResult) -> Void

    var body: some View {
        VStack(spacing: 30) {
            ProgressRing(
                progress: engine.progress,
                accent: accent,
                isOvertime: engine.isOvertime,
                label: engine.displayTime,
                caption: caption
            )
            .frame(width: 240, height: 240)

            HStack(spacing: 14) {
                Button {
                    engine.phase == .paused ? engine.resume() : engine.pause()
                } label: {
                    Label(engine.phase == .paused ? "Resume" : "Pause",
                          systemImage: engine.phase == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button { onEnd(engine.end()) } label: {
                    Label("End session", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
            .frame(maxWidth: 320)
        }
    }

    private var caption: String {
        let name = engine.taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        if engine.phase == .paused { return name.isEmpty ? "Paused" : "Paused · \(name)" }
        return name.isEmpty ? "Focusing" : name
    }
}

// MARK: - Recent history (M3 verification)

private struct RecentSessionsList: View {
    var sessions: [FocusSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(sessions) { session in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: session.activity?.category?.colorHex ?? "#8E8E93"))
                        .frame(width: 8, height: 8)
                    Text(session.activity?.name ?? "Untitled")
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Text(formatDurationShort(seconds: session.elapsedSeconds))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 8))
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}
