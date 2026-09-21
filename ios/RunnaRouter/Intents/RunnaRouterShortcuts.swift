import AppIntents

struct RunnaRouterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateRouteOfDistanceIntent(),
            phrases: [
                "Create a \(\.$distance) route in \(.applicationName)",
                "Create an \(\.$distance) route in \(.applicationName)",
                "Make me a \(\.$distance) route with \(.applicationName)",
                "Make me an \(\.$distance) route with \(.applicationName)",
                "Plan a \(\.$distance) run in \(.applicationName)",
                "Plan an \(\.$distance) run in \(.applicationName)",
            ],
            shortTitle: "Create Route of Distance",
            systemImageName: "point.topleft.down.to.point.bottomright.curvepath"
        )
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
