import SwiftUI
import SwiftData
import AppKit

/// Manage categories: rename inline, recolor, drag-to-reorder, archive/unarchive.
/// A plain VStack (not List) keeps the inline text fields reliably editable on macOS;
/// reordering is a hold-the-handle drag gesture.
struct CategoryManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var dragIndex: Int?
    @State private var dragDY: CGFloat = 0

    private let rowHeight: CGFloat = 38
    private let rowSpacing: CGFloat = 6
    private var slot: CGFloat { rowHeight + rowSpacing }

    private var activeCount: Int { categories.filter { !$0.isArchived }.count }

    private var targetIndex: Int? {
        guard let dragIndex else { return nil }
        let shift = Int((dragDY / slot).rounded())
        return min(categories.count - 1, max(0, dragIndex + shift))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Categories").font(.headline)
                Spacer()
                Button { addCategory() } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: rowSpacing) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        CategoryManagerRow(
                            category: category,
                            canArchive: !category.isArchived && activeCount > 1,
                            isDragging: dragIndex == index,
                            onHandleChanged: { dy in dragIndex = index; dragDY = dy },
                            onHandleEnded: { commitDrag() }
                        )
                        .frame(height: rowHeight)
                        .offset(y: yOffset(for: index))
                        .zIndex(dragIndex == index ? 1 : 0)
                        .animation(.snappy(duration: 0.2), value: targetIndex)
                    }
                }
                .padding(12)
                .removeScrollers()
            }
            .scrollIndicators(.hidden)

            Divider()

            HStack {
                Text("Drag the handle to reorder").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { context.saveSynced(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 480)
    }

    private func yOffset(for index: Int) -> CGFloat {
        guard let dragIndex, let target = targetIndex else { return 0 }
        if index == dragIndex { return dragDY }
        if dragIndex < target, index > dragIndex, index <= target { return -slot }
        if dragIndex > target, index < dragIndex, index >= target { return slot }
        return 0
    }

    private func commitDrag() {
        if let from = dragIndex, let to = targetIndex, from != to {
            var ordered = categories
            let item = ordered.remove(at: from)
            ordered.insert(item, at: to)
            for (i, category) in ordered.enumerated() { category.sortOrder = i }
            context.saveSynced()
        }
        dragIndex = nil
        dragDY = 0
    }

    private func addCategory() {
        let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        let hex = CategoryPalette.swatches[categories.count % CategoryPalette.swatches.count]
        context.insert(Category(name: "New Category", colorHex: hex, sortOrder: nextOrder))
        context.saveSynced()
    }
}

private struct CategoryManagerRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var category: Category
    var canArchive: Bool
    var isDragging: Bool
    var onHandleChanged: (CGFloat) -> Void
    var onHandleEnded: () -> Void

    @State private var showingColors = false

    var body: some View {
        HStack(spacing: 10) {
            handle

            Button { showingColors = true } label: {
                Circle()
                    .fill(Color(hex: category.colorHex))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingColors) { colorGrid }

            TextField("Name", text: $category.name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .onChange(of: category.name) { _, _ in context.saveSynced() }

            if category.isArchived {
                Text("Archived").font(.caption2).foregroundStyle(.tertiary)
            }

            Button {
                category.isArchived.toggle()
                context.saveSynced()
            } label: {
                Image(systemName: category.isArchived ? "tray.and.arrow.up" : "archivebox")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!category.isArchived && !canArchive)
            .help(category.isArchived ? "Unarchive" : "Archive")
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(
            (isDragging ? Color.primary.opacity(0.08) : .clear),
            in: .rect(cornerRadius: 8)
        )
        .shadow(color: isDragging ? .black.opacity(0.25) : .clear, radius: 8, y: 3)
        .opacity(category.isArchived ? 0.55 : 1)
    }

    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 28)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { onHandleChanged($0.translation.height) }
                    .onEnded { _ in onHandleEnded() }
            )
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 4), spacing: 10) {
            ForEach(CategoryPalette.swatches, id: \.self) { swatch in
                Circle()
                    .fill(Color(hex: swatch))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(.primary, lineWidth: category.colorHex == swatch ? 2.5 : 0))
                    .onTapGesture {
                        category.colorHex = swatch
                        context.saveSynced()
                        showingColors = false
                    }
            }
        }
        .padding(14)
    }
}
