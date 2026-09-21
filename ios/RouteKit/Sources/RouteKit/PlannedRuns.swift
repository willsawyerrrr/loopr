import Foundation

/// A calendar event reduced to the fields run planning needs.
public struct CalendarEvent: Hashable, Sendable {
    public var identifier: String
    public var title: String
    public var notes: String?
    public var startDate: Date
    public var isAllDay: Bool

    public init(identifier: String, title: String, notes: String?, startDate: Date, isAllDay: Bool) {
        self.identifier = identifier
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.isAllDay = isAllDay
    }
}

/// A calendar reduced to its identifier and title.
public struct CalendarSummary: Hashable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct NoWorkoutError: LocalizedError, Equatable, Sendable {
    public var errorDescription: String? {
        "This run has no workout details in its calendar notes."
    }
}

/// An all-day Runna calendar event that a route can be generated for.
public struct PlannedRun: Hashable, Identifiable, Sendable {
    /// The event identifier plus the run's date, so recurring events stay distinct.
    public var key: String
    public var title: String
    public var notes: String
    public var date: Date
    /// `yyyy-MM-dd`.
    public var dateString: String

    public var id: String { key }
}

public enum RunPlan {
    /// How many days ahead of the start of today runs are listed.
    public static let windowDays = 8
    /// Local hour at which the morning refresh is scheduled.
    public static let morningHour = 6
    public static let calendarName = "Runna"

    /// All-day events starting in `[startOfToday, startOfToday + 8 days)`, earliest first.
    public static func upcoming(
        _ events: [CalendarEvent], now: Date = .now, calendar: Calendar = .current
    ) -> [PlannedRun] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: windowDays, to: start) else { return [] }
        return events
            .filter { $0.isAllDay && $0.startDate >= start && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
            .map { run(from: $0, calendar: calendar) }
    }

    /// The start of the window, for querying the calendar.
    public static func window(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: windowDays, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// `yyyy-MM-dd` in `calendar`'s time zone.
    public static func dateString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func run(from event: CalendarEvent, calendar: Calendar = .current) -> PlannedRun {
        let date = dateString(event.startDate, calendar: calendar)
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlannedRun(
            key: "\(event.identifier)|\(date)",
            title: title.isEmpty ? "Run" : title,
            notes: event.notes ?? "",
            date: event.startDate,
            dateString: date
        )
    }

    /// The request that asks the server to build a route for `run`'s workout text.
    public static func request(
        for run: PlannedRun,
        start: RoutePoint,
        hillsPreference: Double,
        greenPreference: Double,
        paces: [String: Double]
    ) throws -> RouteRequest {
        guard !run.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NoWorkoutError() }
        return RouteRequest(
            workout: run.notes,
            title: run.title,
            date: run.dateString,
            start: start,
            hillsPreference: hillsPreference,
            greenPreference: greenPreference,
            paces: paces
        )
    }

    /// The chosen calendar if it still exists, otherwise the first whose title contains `Runna`.
    public static func pickCalendar(among calendars: [CalendarSummary], chosenID: String?) -> CalendarSummary? {
        if let chosenID, let chosen = calendars.first(where: { $0.id == chosenID }) { return chosen }
        return calendars.first { $0.title.localizedCaseInsensitiveContains(calendarName) }
    }

    /// The next `morningHour`:00 strictly after `date`.
    public static func nextMorning(after date: Date, calendar: Calendar = .current) -> Date {
        let components = DateComponents(hour: morningHour, minute: 0, second: 0)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(86_400)
    }

    /// Whether a server warning is about a pace phrase missing from the pace table.
    public static func isPaceWarning(_ warning: String) -> Bool {
        warning.hasPrefix("No configured") || warning.contains("pace configured")
    }
}
