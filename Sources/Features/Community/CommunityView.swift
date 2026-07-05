import SwiftUI

struct CommunityView: View {
    @State private var presence = PresenceService.shared
    private let splitBreakpoint: CGFloat = 720

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width >= splitBreakpoint {
                    wideLayout
                } else {
                    narrowLayout
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear { presence.startPolling() }
    }

    // Two columns, each with its own scroll: the radar fills the left column
    // (never shrinking past its overlap-safe minimum); the leaderboards scroll
    // independently on the right.
    private var wideLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                FocusingNowSection(presence: presence)
                    .frame(maxHeight: .infinity)
                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WeeklyLeaderboardSection(presence: presence)
                    StreakLeaderboardSection(presence: presence)
                }
                .padding(24)
                .removeScrollers()
            }
            .scrollIndicators(.hidden)
            .frame(width: 348)
        }
    }

    private var narrowLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FocusingNowSection(presence: presence)
                WeeklyLeaderboardSection(presence: presence)
                StreakLeaderboardSection(presence: presence)
                footer
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            // Center the content block horizontally in the window (.top = centered
            // horizontally, anchored to the top so it still scrolls from the top).
            .frame(maxWidth: .infinity, alignment: .top)
            .removeScrollers()
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var footer: some View {
        if presence.isConfigured, presence.lastError != nil {
            ConnectionIssueFooter(presence: presence)
        }
    }
}

// MARK: - Focusing now

private struct FocusingNowSection: View {
    var presence: PresenceService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Focusing now")
                    .font(.headline)
                if presence.isConfigured, !presence.peers.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("\(presence.peers.count) live")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button { presence.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Community settings")
            }

            if !presence.isConfigured {
                EmptyStateRow(
                    icon: "wifi.slash",
                    title: "Community is offline",
                    message: "Add your Supabase details in Settings to see who else is focusing."
                )
            } else if !presence.hasLoadedPeers {
                PlaceholderRows(count: 2)
            } else if presence.peers.isEmpty {
                EmptyStateRow(
                    icon: "moon.zzz",
                    title: "It's quiet right now",
                    message: "Start a session and you'll show up here for others."
                )
            } else {
                FocusRadar(peers: presence.peers)
            }
        }
    }
}

// MARK: - AirDrop-style radar

private struct FocusRadar: View {
    let peers: [PresencePeer]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: PresencePeer?

    private var ordered: [PresencePeer] {
        peers.sorted { $0.deviceID < $1.deviceID }
    }
    // Flexible height: fills the slack the left column gives it, but never
    // shrinks below a floor sized to keep avatars from overlapping. If the
    // window is smaller than the floor, the column scrolls instead.
    private var minRadar: CGFloat {
        switch ordered.count {
        case 0...4: return 240
        case 5...7: return 300
        default: return 340
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let available = min(geo.size.width, geo.size.height, 440)
                let maxRadius = min(170, max(80, available / 2 - 52))
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    RadarBackdrop(radius: maxRadius, animate: !reduceMotion)
                        .position(center)
                    CenterHub()
                        .position(center)
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, peer in
                        let slot = layout(index: index, count: ordered.count, maxRadius: maxRadius)
                        PeerNode(peer: peer, index: index, isHovered: hovered?.id == peer.id) { hovering in
                            hovered = hovering ? peer : (hovered?.id == peer.id ? nil : hovered)
                        }
                        .position(x: center.x + slot.radius * cos(slot.angle),
                                  y: center.y + slot.radius * sin(slot.angle))
                    }
                }
            }
            .frame(minHeight: minRadar, maxHeight: .infinity)

            Text(hovered.map(detail) ?? "Hover a dot to see what they're working on.")
                .font(.caption2)
                .foregroundStyle(hovered == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.15), value: hovered)
        }
        .frame(maxWidth: .infinity)
    }

    private func detail(_ peer: PresencePeer) -> String {
        let task = peer.taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPart = (task?.isEmpty == false) ? task! : "Working"
        let status: String
        if peer.isPaused {
            status = "Paused"
        } else {
            let planned = max(0, peer.plannedMinutes * 60)
            status = planned > 0 ? "\(formatDurationShort(seconds: max(0, planned - peer.elapsedSeconds))) left" : "Focusing"
        }
        return "\(peer.nickname) · \(taskPart) · \(status)"
    }

    // Small crowds sit on one ring; larger ones split across an inner and
    // outer ring (AirDrop-style) so avatars don't collide.
    private func layout(index: Int, count: Int, maxRadius: CGFloat) -> (radius: CGFloat, angle: Double) {
        if count <= 4 {
            return (maxRadius, -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(1, count)))
        }
        let inner = max(1, count / 3)
        if index < inner {
            return (maxRadius * 0.48, -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(inner))
        }
        let outerCount = count - inner
        let outerIndex = index - inner
        let angle = -Double.pi / 2 + Double.pi / Double(outerCount)
            + 2 * Double.pi * Double(outerIndex) / Double(outerCount)
        return (maxRadius, angle)
    }
}

private struct RadarBackdrop: View {
    let radius: CGFloat
    let animate: Bool
    @State private var ping = false

    var body: some View {
        ZStack {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    .frame(width: radius * 2 * CGFloat(i) / 3, height: radius * 2 * CGFloat(i) / 3)
            }
            if animate {
                Circle()
                    .stroke(Color.accentColor.opacity(ping ? 0 : 0.22), lineWidth: 1.5)
                    .frame(width: radius * 2, height: radius * 2)
                    .scaleEffect(ping ? 1.08 : 0.35)
                    .onAppear {
                        withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)) {
                            ping = true
                        }
                    }
            }
        }
    }
}

private struct CenterHub: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("You")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PeerNode: View {
    let peer: PresencePeer
    let index: Int
    var isHovered: Bool = false
    var onHover: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    private var color: Color { Color(hex: peer.categoryColor ?? "#8E8E93") }

    // Distinct per-peer bob: duration + phase varied by index so no two
    // avatars rise and fall in lockstep.
    private var hash: Double {
        var h = UInt64(1469598103934665603)
        for byte in peer.deviceID.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return Double(h % 1000) / 1000.0
    }
    private var amplitude: CGFloat { 3 }
    private var duration: Double { 1.8 + hash * 0.8 + Double(index) * 0.15 }
    private var phaseDelay: Double { Double(index) * 0.45 }

    var body: some View {
        avatar
            .scaleEffect(isHovered ? 1.15 : 1)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .offset(y: bob ? -amplitude : amplitude)
            .animation(reduceMotion ? nil :
                .easeInOut(duration: duration).repeatForever(autoreverses: true).delay(phaseDelay),
                value: bob)
            .onAppear { bob = true }
            .onHover { onHover($0) }
            .help(tooltip)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 3)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .fill(color.opacity(0.16))
                .padding(4)
            Text(initials)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(width: 50, height: 50)
        .grayscale(peer.isPaused ? 0.85 : 0)
        .opacity(peer.isPaused ? 0.7 : 1)
        .overlay(alignment: .bottomTrailing) {
            if peer.isPaused {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            }
        }
    }

    private var initials: String {
        let words = peer.nickname.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var fraction: CGFloat? {
        let planned = CGFloat(max(0, peer.plannedMinutes * 60))
        guard planned > 0 else { return nil }
        return min(1, max(0.02, CGFloat(peer.elapsedSeconds) / planned))
    }

    private var tooltip: String {
        let task = peer.taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPart = task?.isEmpty == false ? " · \(task!)" : ""
        return "\(peer.nickname)\(taskPart) · \(statusText)"
    }

    private var statusText: String {
        if peer.isPaused { return "Paused" }
        let plannedSeconds = max(0, peer.plannedMinutes * 60)
        guard plannedSeconds > 0 else { return "Focusing" }
        return "\(formatDurationShort(seconds: max(0, plannedSeconds - peer.elapsedSeconds))) left"
    }
}

// MARK: - Weekly leaderboard

private struct WeeklyLeaderboardSection: View {
    var presence: PresenceService
    private var top: [WeeklyLeader] { Array(presence.weeklyLeaders.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.headline)
                Spacer()
                Text("vs last week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Ranked by focus time")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !presence.isConfigured {
                EmptyStateRow(
                    icon: "trophy",
                    title: "Leaderboard unavailable",
                    message: "Connect the community to compete on weekly focus time."
                )
            } else if !presence.hasLoadedLeaders {
                PlaceholderRows(count: 4)
            } else if top.isEmpty {
                EmptyStateRow(
                    icon: "trophy",
                    title: "No leaders yet",
                    message: "Finish a session this week to claim the first spot."
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, leader in
                        WeeklyLeaderRow(rank: index + 1, leader: leader)
                    }
                    if let me = currentUserOutsideTop {
                        HStack {
                            Spacer()
                            Image(systemName: "ellipsis").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        WeeklyLeaderRow(rank: me.rank, leader: me.leader)
                    }
                }
            }
        }
    }

    private var currentUserOutsideTop: (rank: Int, leader: WeeklyLeader)? {
        guard let index = presence.weeklyLeaders.firstIndex(where: \.isCurrentUser), index >= 5 else { return nil }
        return (index + 1, presence.weeklyLeaders[index])
    }
}

private struct WeeklyLeaderRow: View {
    let rank: Int
    let leader: WeeklyLeader

    var body: some View {
        HStack(spacing: 10) {
            rankMarker
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(leader.isCurrentUser ? "You" : leader.nickname)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    rankChange
                    Spacer(minLength: 6)
                    Text(formatDurationShort(seconds: leader.totalSeconds))
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(leader.isCurrentUser ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: .rect(cornerRadius: 8))
    }

    @ViewBuilder private var rankMarker: some View {
        if rank <= 3 {
            Text(["🥇", "🥈", "🥉"][rank - 1])
                .font(.system(size: 17))
        } else {
            Text("\(rank)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var rankChange: some View {
        if let delta = leader.rankDelta {
            if delta > 0 {
                changeChip(symbol: "arrow.up", value: "\(delta)", color: .green)
            } else if delta < 0 {
                changeChip(symbol: "arrow.down", value: "\(-delta)", color: .red)
            } else {
                Text("–")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("NEW")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .padding(.vertical, 1)
                .padding(.horizontal, 4)
                .background(Color.accentColor.opacity(0.14), in: .capsule)
        }
    }

    private func changeChip(symbol: String, value: String, color: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol)
            Text(value)
        }
        .font(.caption2.weight(.bold).monospacedDigit())
        .foregroundStyle(color)
    }

    private var metaLine: String {
        "\(leader.sessionCount) session\(leader.sessionCount == 1 ? "" : "s")"
    }
}

// MARK: - Streak leaderboard

private struct StreakLeaderboardSection: View {
    var presence: PresenceService

    private var ranked: [WeeklyLeader] {
        presence.weeklyLeaders
            .filter { $0.streakDays > 0 }
            .sorted {
                if $0.streakDays != $1.streakDays { return $0.streakDays > $1.streakDays }
                return $0.bestStreakDays > $1.bestStreakDays
            }
    }
    private var top: [WeeklyLeader] { Array(ranked.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Longest streaks")
                    .font(.headline)
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text("This week · most consecutive focus days")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !presence.isConfigured {
                EmptyStateRow(
                    icon: "flame",
                    title: "Streaks unavailable",
                    message: "Connect the community to track focus streaks."
                )
            } else if !presence.hasLoadedLeaders {
                PlaceholderRows(count: 3)
            } else if top.isEmpty {
                EmptyStateRow(
                    icon: "flame",
                    title: "No streaks yet",
                    message: "Focus two days in a row to start a streak."
                )
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, leader in
                        StreakLeaderRow(rank: index + 1, leader: leader)
                    }
                    if let me = currentUserOutsideTop {
                        HStack {
                            Spacer()
                            Image(systemName: "ellipsis").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        StreakLeaderRow(rank: me.rank, leader: me.leader)
                    }
                }
            }
        }
    }

    private var currentUserOutsideTop: (rank: Int, leader: WeeklyLeader)? {
        guard let index = ranked.firstIndex(where: \.isCurrentUser), index >= 5 else { return nil }
        return (index + 1, ranked[index])
    }
}

private struct StreakLeaderRow: View {
    let rank: Int
    let leader: WeeklyLeader

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(rank == 1 ? .orange : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(leader.isCurrentUser ? "You" : leader.nickname)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                        Text("\(leader.streakDays)d")
                    }
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                }
                Text(recordLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(leader.isCurrentUser ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: .rect(cornerRadius: 8))
    }

    private var recordLine: String {
        if leader.streakDays >= leader.bestStreakDays {
            return "On their longest streak yet"
        }
        return "Best: \(leader.bestStreakDays) days"
    }
}

// MARK: - Shared states

private struct EmptyStateRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 8))
    }
}

private struct PlaceholderRows: View {
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 10) {
                    Circle().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Placeholder name")
                            .font(.callout.weight(.medium))
                        Text("Working on something")
                            .font(.caption)
                    }
                    Spacer()
                    Text("00m")
                        .font(.caption.monospacedDigit())
                }
                .redacted(reason: .placeholder)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
        }
    }
}

private struct ConnectionIssueFooter: View {
    var presence: PresenceService

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("Can't reach the community server right now.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") { presence.refresh() }
                .buttonStyle(.link)
                .font(.caption)
        }
        .help(presence.lastError ?? "")
    }
}
