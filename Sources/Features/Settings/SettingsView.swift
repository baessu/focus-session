import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(SoundKeys.backgroundOn) private var backgroundOn = false
    @AppStorage(SoundKeys.startSound) private var startSound = SystemSound.morse.rawValue
    @AppStorage(SoundKeys.endSound) private var endSound = SystemSound.glass.rawValue
    @AppStorage(SoundKeys.startVolume) private var startVolume = 0.6
    @AppStorage(SoundKeys.endVolume) private var endVolume = 0.6
    @AppStorage(PresenceKeys.nickname) private var nickname = ""
    @AppStorage(PresenceKeys.emoji) private var emoji = ""
    @AppStorage(PresenceKeys.publishTaskName) private var publishTaskName = false
    @FocusState private var nameFocused: Bool
    @FocusState private var iconFocused: Bool
    @Environment(\.modelContext) private var context
    @State private var syncedCount: Int?
    @State private var sync = SyncService.shared
    @State private var recovering = false
    @State private var recoverResult: String?

    var body: some View {
        Form {
            Section("Community profile") {
                HStack(spacing: 10) {
                    Text("Display name")
                    Spacer(minLength: 0)
                    TextField("", text: $nickname, prompt: Text("Your community name"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .focused($nameFocused)
                }
                HStack(spacing: 10) {
                    Text("Display icon")
                    Spacer(minLength: 0)
                    TextField("", text: $emoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .multilineTextAlignment(.center)
                        .focused($iconFocused)
                        .onChange(of: iconFocused) { _, focused in
                            if focused { NSApp.orderFrontCharacterPalette(nil) }
                        }
                        .onChange(of: emoji) { _, value in
                            let first = value.first.map(String.init) ?? ""
                            if emoji != first { emoji = first }
                        }
                }
                Text("Your avatar in the community. Leave empty to show your initials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Share what I'm working on", isOn: $publishTaskName)
                Text(publishTaskName
                     ? "Others will see your task name (e.g. \u{201C}Writing report\u{201D}) while you focus."
                     : "Others see only that you're focusing \u{2014} never your task name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProfilePreview(name: displayName, emoji: emoji, showsTask: publishTaskName)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                HStack {
                    Button {
                        syncedCount = backfillCommunity(context: context)
                    } label: {
                        Label("Re-sync my sessions", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Spacer(minLength: 0)
                    if let syncedCount {
                        Text("\(syncedCount) queued")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Publishes your recent sessions (last 35 days) to the weekly leaderboard, including ones added on the timetable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        recovering = true
                        recoverResult = nil
                        Task {
                            let result = await PresenceService.shared.recoverSessionsFromServer(context: context)
                            recovering = false
                            recoverResult = "\(result.inserted) recovered · \(result.total) on server"
                        }
                    } label: {
                        Label("Recover sessions from server", systemImage: "arrow.down.circle")
                    }
                    .disabled(recovering)
                    Spacer(minLength: 0)
                    if recovering {
                        ProgressView().controlSize(.small)
                    } else if let recoverResult {
                        Text(recoverResult).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Lost your local history? This rebuilds sessions from your community summaries (time and rating only — task names weren't uploaded). Safe to run repeatedly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sync across devices") {
                if let path = sync.folderPath {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync folder").font(.caption).foregroundStyle(.secondary)
                            Text(shortPath(path))
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button("Change") { pickSyncFolder() }
                        Button("Remove") { sync.clearFolder() }
                    }

                    HStack {
                        Button {
                            sync.syncNow(context: context)
                        } label: {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(sync.isSyncing)
                        Spacer(minLength: 0)
                        if sync.isSyncing {
                            ProgressView().controlSize(.small)
                        } else if let last = sync.lastSync {
                            Text("Last synced \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = sync.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Text("Your sessions are saved as a file in this folder and merged across your Macs. Nothing is sent to a server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button { pickSyncFolder() } label: {
                        Label("Choose sync folder…", systemImage: "folder.badge.plus")
                    }
                    Text("Pick a folder your other Mac also syncs (iCloud Drive, Dropbox, …). FocusSession keeps your data there — no server, no account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Background sound", isOn: $backgroundOn)
                Text("Keeps the app active in the background so FocusSession can still alert you when a session ends, even in Focus mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Session start sound") {
                soundPicker(selection: $startSound, volume: $startVolume)
            }

            Section("Session end sound") {
                soundPicker(selection: $endSound, volume: $endVolume)
            }

            Section("Feedback") {
                Link(destination: feedbackMailURL) {
                    Label("Send feedback / report a bug", systemImage: "envelope")
                }
                Text("Opens your mail app to write to heymoana321@gmail.com — ideas and bugs are welcome.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://buymeacoffee.com/heymoana")!) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer")
                }
                Text("Enjoying FocusSession? A coffee helps keep it going.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 620)
        .onAppear {
            if nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nickname = PresenceService.shared.nickname
            }
            // Don't open with the name field focused/selected.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                nameFocused = false
            }
        }
    }

    private var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PresenceService.shared.nickname : trimmed
    }

    private func pickSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a folder inside your iCloud Drive, Dropbox, or another synced location."
        if panel.runModal() == .OK, let url = panel.url {
            sync.setFolder(url)
        }
    }

    /// Shows the last two path components so a long folder path stays readable.
    private func shortPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    private var feedbackMailURL: URL {
        let subject = "FocusSession Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:heymoana321@gmail.com?subject=\(subject)")!
    }

    @ViewBuilder
    private func soundPicker(selection: Binding<String>, volume: Binding<Double>) -> some View {
        HStack {
            Picker("Sound", selection: selection) {
                ForEach(SystemSound.allCases) { sound in
                    Text(sound.rawValue).tag(sound.rawValue)
                }
            }
            .labelsHidden()
            Button {
                SoundManager.preview(selection.wrappedValue, volume: volume.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Preview")
        }
        HStack(spacing: 10) {
            Text("Volume").font(.caption).foregroundStyle(.secondary)
            Slider(value: volume, in: 0...1)
            Image(systemName: "speaker.wave.2").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Shows how the person will appear to others in the community radar.
private struct ProfilePreview: View {
    let name: String
    let emoji: String
    let showsTask: Bool

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.16))
                if emoji.isEmpty {
                    Text(initials)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(emoji).font(.system(size: 20))
                }
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(showsTask ? "Writing report \u{00B7} 25m left" : "Focusing \u{00B7} 25m left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Preview")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 8))
    }
}
