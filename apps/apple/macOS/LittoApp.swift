import SwiftData
import SwiftUI

@main
struct LittoApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        container = Store.makeContainer()
        Reminder.shared.activate()
        FolderSync.shared.start(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { FolderSync.shared.scan() } else { FolderSync.shared.exportProgress() }
        }

        .commands { LittoCommands() }

        Settings {
            SettingsView()
        }
    }
}

/// Everything is reachable from the keyboard.
struct LittoCommands: Commands {
    private let router = AppRouter.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import…") { router.importing = true }
                .keyboardShortcut("o")
        }
        CommandMenu("Study") {
            Button("Start today's review") { router.startToday = true }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Study selected deck") { router.studySelectedDeck = true }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("See today's words") { router.showTodayWords = true }
                .keyboardShortcut("l")
        }
    }
}
