import Foundation
import Observation

enum AppTab: Hashable {
    case generate
    case saved
}

/// Lets App Intents steer the UI.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    var tab = AppTab.generate
    var savedPath: [UUID] = []

    func show(routeID: UUID) {
        tab = .saved
        savedPath = [routeID]
    }
}
