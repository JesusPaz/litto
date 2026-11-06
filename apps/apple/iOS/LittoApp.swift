import SwiftData
import SwiftUI

@main
struct LittoApp: App {
    let container: ModelContainer

    init() {
        container = Store.makeContainer()
        Reminder.shared.activate()
        #if DEBUG
        Demo.seed(container.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
