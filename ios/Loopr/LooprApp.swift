import SwiftData
import SwiftUI

@main
struct LooprApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LooprShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(RouteStore.container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { MorningRefresh.schedule() }
        }
        .backgroundTask(.appRefresh(MorningRefresh.identifier)) {
            await MorningRefresh.perform()
        }
    }
}
