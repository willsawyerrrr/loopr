import SwiftData
import SwiftUI

@main
struct LooprApp: App {
    init() {
        LooprShortcuts.updateAppShortcutParameters()
        MorningRefresh.schedule()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(RouteStore.container)
        .backgroundTask(.appRefresh(MorningRefresh.identifier)) {
            await MorningRefresh.perform()
        }
    }
}
