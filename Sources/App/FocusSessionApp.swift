import SwiftUI
import SwiftData
import AppKit
import Sparkle

@main
struct FocusSessionApp: App {
    @State private var engine = FocusTimerEngine.shared
    // Sparkle auto-updater: checks the appcast, downloads, installs, relaunches.
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                                updaterDelegate: nil,
                                                                userDriverDelegate: nil)
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainerFactory.make()
        } catch {
            fatalError("Failed to open FocusSession data store: \(error)")
        }
    }()

    init() {
        // Carry the community identity over from the pre-1.2 sandbox container.
        PresenceDefaultsMigration.runIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowResizability(.contentMinSize)
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.updater.checkForUpdates()
                }
                Button("Send Feedback…") {
                    let subject = "FocusSession Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "mailto:heymoana321@gmail.com?subject=\(subject)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Buy Me a Coffee…") {
                    if let url = URL(string: "https://buymeacoffee.com/heymoana") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)

        // A live countdown in the menu bar, present only while a session runs.
        MenuBarExtra(isInserted: .constant(engine.phase != .idle)) {
            MenuBarContent(engine: engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
    }
}

private struct MenuBarLabel: View {
    var engine: FocusTimerEngine

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
            Text(engine.displayTime)
                .monospacedDigit()
                .frame(minWidth: 46, alignment: .center)
        }
    }
}

private struct MenuBarContent: View {
    var engine: FocusTimerEngine

    var body: some View {
        let name = engine.taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        Text(name.isEmpty ? "Focus session" : name)
        Text(engine.isOvertime ? "Overtime \(engine.displayTime)" : "\(engine.displayTime) left")

        Divider()

        Button(engine.phase == .paused ? "Resume" : "Pause") {
            if engine.phase == .paused { engine.resume() } else { engine.pause() }
        }

        Button("Open FocusSession") {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}
