import SwiftData
import SwiftUI

@main
struct LooprApp: App {
    init() {
        LooprShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(RouteStore.container)
    }
}
