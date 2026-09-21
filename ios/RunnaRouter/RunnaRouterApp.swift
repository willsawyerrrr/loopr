import SwiftData
import SwiftUI

@main
struct RunnaRouterApp: App {
    init() {
        RunnaRouterShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(RouteStore.container)
    }
}
