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

        Settings {
            SettingsView()
        }
    }
}
