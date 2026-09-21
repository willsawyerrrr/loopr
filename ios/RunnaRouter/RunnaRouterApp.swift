import RouteKit
import SwiftData
import SwiftUI

@main
struct RunnaRouterApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try MainActor.assumeIsolated { try SavedRoute.makeContainer() }
        } catch {
            fatalError("Could not open the route store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
