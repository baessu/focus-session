import SwiftUI

struct SettingsView: View {
    @AppStorage(SoundKeys.backgroundOn) private var backgroundOn = false
    @AppStorage(SoundKeys.startSound) private var startSound = SystemSound.morse.rawValue
    @AppStorage(SoundKeys.endSound) private var endSound = SystemSound.glass.rawValue
    @AppStorage(SoundKeys.startVolume) private var startVolume = 0.6
    @AppStorage(SoundKeys.endVolume) private var endVolume = 0.6

    var body: some View {
        Form {
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
        .frame(width: 440, height: 460)
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
