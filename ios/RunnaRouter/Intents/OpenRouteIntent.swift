import AppIntents

struct OpenRouteIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Route"
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Route")
    var target: RouteEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.show(routeID: target.id)
        return .result()
    }
}
