import EventKit
import Foundation
import RouteKit

/// Reads the Runna calendar through EventKit and hands the events to `RunPlan`.
@MainActor
enum RunCalendar {
    enum Access {
        case granted
        case notDetermined
        case denied
    }

    static let chosenCalendarKey = "runCalendarID"

    private static let store = EKEventStore()

    static var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func calendars() -> [CalendarSummary] {
        store.calendars(for: .event).map { CalendarSummary(id: $0.calendarIdentifier, title: $0.title) }
    }

    static func selectedCalendar() -> CalendarSummary? {
        let chosen = UserDefaults.standard.string(forKey: chosenCalendarKey)
        return RunPlan.pickCalendar(among: calendars(), chosenID: chosen?.isEmpty == false ? chosen : nil)
    }

    /// The upcoming runs, or `nil` when no calendar is selected.
    static func upcomingRuns(now: Date = .now) -> [PlannedRun]? {
        guard let selected = selectedCalendar(),
            let calendar = store.calendar(withIdentifier: selected.id)
        else { return nil }
        let window = RunPlan.window(now: now)
        let events = store.events(
            matching: store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
        ).map {
            CalendarEvent(
                identifier: $0.eventIdentifier ?? $0.calendarItemIdentifier, title: $0.title ?? "", notes: $0.notes,
                startDate: $0.startDate, isAllDay: $0.isAllDay)
        }
        return RunPlan.upcoming(events, now: now)
    }
}
