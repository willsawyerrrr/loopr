import AppIntents

struct RunnaRouterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateRouteIntent(),
            phrases: [
                "Create a route in \(.applicationName)",
                "Make me a route with \(.applicationName)",
                "Generate a run route with \(.applicationName)",
                "Plan a run in \(.applicationName)",
            ],
            shortTitle: "Create Route",
            systemImageName: "point.topleft.down.to.point.bottomright.curvepath"
        )
        AppShortcut(
            intent: OpenRouteIntent(),
            phrases: ["Open \(\.$target) in \(.applicationName)"],
            shortTitle: "Open Route",
            systemImageName: "bookmark"
        )
    }
}
