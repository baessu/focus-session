import AppKit

/// Built-in macOS system sounds offered for session start / end cues.
enum SystemSound: String, CaseIterable, Identifiable {
    case tink = "Tink"
    case pop = "Pop"
    case morse = "Morse"
    case purr = "Purr"
    case bottle = "Bottle"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case ping = "Ping"
    case submarine = "Submarine"
    case sosumi = "Sosumi"
    case frog = "Frog"

    var id: String { rawValue }
}

/// UserDefaults keys shared by SettingsView (@AppStorage) and the player.
enum SoundKeys {
    static let backgroundOn = "soundBackgroundOn"
    static let startSound = "soundStart"
    static let endSound = "soundEnd"
    static let startVolume = "soundStartVolume"
    static let endVolume = "soundEndVolume"
}

@MainActor
enum SoundManager {
    static func playStart() {
        play(name: defaults.string(forKey: SoundKeys.startSound) ?? SystemSound.morse.rawValue,
             volume: volume(SoundKeys.startVolume))
    }

    static func playEnd() {
        play(name: defaults.string(forKey: SoundKeys.endSound) ?? SystemSound.glass.rawValue,
             volume: volume(SoundKeys.endVolume))
    }

    static func preview(_ name: String, volume: Double) {
        play(name: name, volume: volume)
    }

    private static var defaults: UserDefaults { .standard }

    private static func volume(_ key: String) -> Double {
        defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : 0.6
    }

    private static func play(name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = Float(volume)
        sound.play()
    }
}
