import SwiftUI

struct StatsRangeBar: View {
    @Binding var range: StatsRange
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { range = range.shifted(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .disabled(!range.isNavigable)
                    .opacity(range.isNavigable ? 1 : 0.3)

                Button { showPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(range.title()).font(.headline)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.primary.opacity(0.06), in: .capsule)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPicker) {
                    RangePickerPopover(range: $range, isPresented: $showPicker)
                }

                Button { range = range.shifted(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(!range.isNavigable)
                    .opacity(range.isNavigable ? 1 : 0.3)
            }

            Text(range.rangeSpanLabel())
                .font(.caption)
                .foregroundStyle(.secondary)

            if range.isNavigable {
                HStack(spacing: 8) {
                    ForEach(Array(range.chips().enumerated()), id: \.offset) { _, chip in
                        let selected = chip == range
                        let lines = chip.chipLines()
                        Button { range = chip } label: {
                            VStack(spacing: 1) {
                                Text(lines.top).font(.caption2).foregroundStyle(.tertiary)
                                Text(lines.bottom).font(.caption.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                selected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04),
                                in: .rect(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct RangePickerPopover: View {
    @Binding var range: StatsRange
    @Binding var isPresented: Bool

    private func choose(_ r: StatsRange) { range = r; isPresented = false }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                quickUnit("Day", .today())
                quickUnit("Week", .thisWeek())
                quickUnit("Month", .thisMonth())
            }
            .padding(.bottom, 6)

            Divider().padding(.bottom, 4)

            preset("Today", .today())
            preset("Yesterday", .yesterday())
            preset("This Week", .thisWeek())
            preset("Last Week", .lastWeek())
            preset("This Month", .thisMonth())
            preset("Last Month", .lastMonth())
            preset("Last 7 Days", .rolling(7))
            preset("Last 14 Days", .rolling(14))
            preset("Last 28 Days", .rolling(28))
        }
        .padding(10)
        .frame(width: 230)
    }

    private func quickUnit(_ title: String, _ r: StatsRange) -> some View {
        Button { choose(r) } label: {
            Text(title)
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(sameMode(r) ? Color.accentColor : Color.primary.opacity(0.06),
                           in: .rect(cornerRadius: 8))
                .foregroundStyle(sameMode(r) ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func sameMode(_ r: StatsRange) -> Bool {
        switch (range.mode, r.mode) {
        case (.day, .day), (.week, .week), (.month, .month): return true
        default: return false
        }
    }

    private func preset(_ title: String, _ r: StatsRange) -> some View {
        Button { choose(r) } label: {
            HStack {
                Text(title)
                Spacer()
                if range == r { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
