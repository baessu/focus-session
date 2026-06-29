import SwiftUI
import SwiftData
import AppKit

@main
struct FocusSessionApp: App {
    @State private var engine = FocusTimerEngine.shared

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowResizability(.contentMinSize)
        .modelContainer(for: [Category.self, Activity.self, FocusSession.self])

        Settings {
            SettingsView()
        }

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
            Image(systemName: engine.isOvertime ? "timer" : "timer")
            Text(engine.displayTime).monospacedDigit()
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
