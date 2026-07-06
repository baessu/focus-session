import SwiftUI

struct SettingsView: View {
    @AppStorage(SoundKeys.backgroundOn) private var backgroundOn = false
    @AppStorage(SoundKeys.startSound) private var startSound = SystemSound.morse.rawValue
    @AppStorage(SoundKeys.endSound) private var endSound = SystemSound.glass.rawValue
    @AppStorage(SoundKeys.startVolume) private var startVolume = 0.6
    @AppStorage(SoundKeys.endVolume) private var endVolume = 0.6
    @AppStorage(PresenceKeys.nickname) private var nickname = ""
    @AppStorage(PresenceKeys.publishTaskName) private var publishTaskName = false
    @FocusState private var nameFocused: Bool
    @Environment(\.modelContext) private var context
    @State private var syncedCount: Int?

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
                Text("This is the only thing others see. Your real name and device stay private.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Share what I'm working on", isOn: $publishTaskName)
                Text(publishTaskName
                     ? "Others will see your task name (e.g. \u{201C}Writing report\u{201D}) while you focus."
                     : "Others see only that you're focusing \u{2014} never your task name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProfilePreview(name: displayName, showsTask: publishTaskName)
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
                Text(initials)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
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
