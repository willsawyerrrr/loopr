import BackgroundTasks
import Foundation
import RouteKit
import UserNotifications

/// Prepares the next run's route in a background refresh around 06:00. iOS decides when (and whether) it runs.
@MainActor
enum MorningRefresh {
    static let identifier = "dev.willsawyerrrr.Loopr.refresh"
    static let enabledKey = "prepareRoutesEachMorning"

    private static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks for notification permission and, if granted, turns the refresh on.
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        schedule()
        return granted
    }

    /// Requests the next refresh for the coming 06:00, or cancels it when the setting is off.
    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = RunPlan.nextMorning(after: .now)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Generates the route for today's run (or the next one) if it is missing, and notifies.
    static func perform() async {
        guard isEnabled else { return }
        defer { schedule() }
        guard RunCalendar.access == .granted, let run = RunCalendar.upcomingRuns()?.first,
            RouteStore.route(forEventKey: run.key) == nil,
            let route = try? await RunPreparation.prepare(run, background: true)
        else { return }
        let content = UNMutableNotificationContent()
        content.title = "Route ready: \(run.title) · \(RouteFormat.distance(km: route.distanceKm))"
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: run.key, content: content, trigger: nil))
    }
}
