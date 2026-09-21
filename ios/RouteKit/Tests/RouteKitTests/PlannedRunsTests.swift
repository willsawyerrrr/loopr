import Foundation
import SwiftData
import Testing

@testable import RouteKit

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func date(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)!
}

private func event(
    _ id: String, _ start: String, title: String = "Easy Run", notes: String? = "5km at conversational pace",
    allDay: Bool = true
) -> CalendarEvent {
    CalendarEvent(identifier: id, title: title, notes: notes, startDate: date(start), isAllDay: allDay)
}

@Suite struct RunPlanTests {
    private let now = date("2026-09-22T15:30:00Z")

    @Test func selectsAllDayEventsInWindowEarliestFirst() {
        let events = [
            event("late", "2026-09-28T00:00:00Z"),
            event("today", "2026-09-22T00:00:00Z"),
            event("yesterday", "2026-09-21T00:00:00Z"),
            event("edge", "2026-09-30T00:00:00Z"),
            event("timed", "2026-09-24T09:00:00Z", allDay: false),
            event("soon", "2026-09-23T00:00:00Z"),
        ]
        let runs = RunPlan.upcoming(events, now: now, calendar: utc)
        #expect(runs.map(\.key) == ["today|2026-09-22", "soon|2026-09-23", "late|2026-09-28"])
    }

    @Test func includesTodaysRunThatStartedAtMidnight() {
        let runs = RunPlan.upcoming([event("a", "2026-09-22T00:00:00Z")], now: now, calendar: utc)
        #expect(runs.count == 1)
    }

    @Test func windowEndsEightDaysAfterStartOfToday() {
        let window = RunPlan.window(now: now, calendar: utc)
        #expect(window.start == date("2026-09-22T00:00:00Z"))
        #expect(window.end == date("2026-09-30T00:00:00Z"))
    }

    @Test func recurringEventsKeepDistinctKeys() {
        let runs = RunPlan.upcoming(
            [event("same", "2026-09-22T00:00:00Z"), event("same", "2026-09-23T00:00:00Z")], now: now, calendar: utc)
        #expect(Set(runs.map(\.key)).count == 2)
    }

    @Test func buildsWorkoutRequest() throws {
        let run = RunPlan.run(from: event("a", "2026-09-22T00:00:00Z", title: " Tempo "), calendar: utc)
        let request = try RunPlan.request(
            for: run, start: RoutePoint(longitude: 151.2, latitude: -33.8), hillsPreference: 0.5, greenPreference: 0.25,
            paces: ["walking": 11])
        let json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["workout"] as? String == "5km at conversational pace")
        #expect(json["title"] as? String == "Tempo")
        #expect(json["date"] as? String == "2026-09-22")
        #expect(json["start"] as? [Double] == [151.2, -33.8])
        #expect(json["hillsPreference"] as? Double == 0.5)
        #expect(json["greenPreference"] as? Double == 0.25)
        #expect(json["paces"] as? [String: Double] == ["walking": 11])
        #expect(json["targetDistanceKm"] == nil)
    }

    @Test func rejectsRunsWithoutNotes() {
        for notes in [nil, "  \n"] {
            let run = RunPlan.run(from: event("a", "2026-09-22T00:00:00Z", notes: notes), calendar: utc)
            #expect(throws: NoWorkoutError.self) {
                try RunPlan.request(
                    for: run, start: RoutePoint(longitude: 0, latitude: 0), hillsPreference: 0, greenPreference: 0,
                    paces: [:])
            }
        }
    }

    @Test func picksChosenCalendarThenRunna() {
        let calendars = [
            CalendarSummary(id: "1", title: "Work"),
            CalendarSummary(id: "2", title: "my RUNNA plan"),
            CalendarSummary(id: "3", title: "Family"),
        ]
        #expect(RunPlan.pickCalendar(among: calendars, chosenID: nil)?.id == "2")
        #expect(RunPlan.pickCalendar(among: calendars, chosenID: "3")?.id == "3")
        #expect(RunPlan.pickCalendar(among: calendars, chosenID: "gone")?.id == "2")
        #expect(RunPlan.pickCalendar(among: Array(calendars.prefix(1)), chosenID: nil) == nil)
    }

    @Test func nextMorningIsSixAmStrictlyAfter() {
        #expect(RunPlan.nextMorning(after: date("2026-09-22T05:00:00Z"), calendar: utc) == date("2026-09-22T06:00:00Z"))
        #expect(RunPlan.nextMorning(after: date("2026-09-22T06:00:00Z"), calendar: utc) == date("2026-09-23T06:00:00Z"))
        #expect(RunPlan.nextMorning(after: date("2026-09-22T18:00:00Z"), calendar: utc) == date("2026-09-23T06:00:00Z"))
    }

    @Test func recognisesPaceWarnings() {
        #expect(RunPlan.isPaceWarning(#"No configured pace for "tempo"; using fallback 7.5 min/km"#))
        #expect(RunPlan.isPaceWarning(#"No "walking" pace configured; using 11 min/km"#))
        #expect(!RunPlan.isPaceWarning("No segments parsed from workout text"))
    }
}

@Suite struct PaceStoreTests {
    private func store() -> PaceStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return PaceStore(defaults: defaults)
    }

    @Test func seedsWithServerDefaults() {
        #expect(store().paces == ["walking": 11.0, "conversational pace": 7.5])
    }

    @Test func savesCleanedPaces() {
        let store = store()
        store.save([" Tempo Pace ": 5.0, "": 6, "bad": 0, "walking": 12])
        #expect(store.paces == ["tempo pace": 5.0, "walking": 12])
    }
}

@Suite @MainActor struct EventRouteTests {
    @Test func storesEventKeyAndWarningsAndUpdatesInPlace() throws {
        let container = try SavedRoute.makeContainer(inMemory: true)
        let summary = RouteSummary(distanceKm: 3, ascentM: 10, descentM: 9, elevationGainPerKm: 3.3, hilliness: "flat", greenScore: 0)
        let route = SavedRoute(
            name: "Easy Run", targetDistanceKm: 3, summary: summary, previewUrl: nil,
            points: [RoutePoint(longitude: 1, latitude: 2)], warnings: ["careful"], eventKey: "a|2026-09-22")
        container.mainContext.insert(route)
        try container.mainContext.save()

        let key = "a|2026-09-22"
        let found = try container.mainContext.fetch(
            FetchDescriptor<SavedRoute>(predicate: #Predicate { $0.eventKey == key }))
        #expect(found.count == 1)
        #expect(found[0].warnings == ["careful"])

        let updated = RouteSummary(distanceKm: 5, ascentM: 1, descentM: 1, elevationGainPerKm: 0.2, hilliness: "flat", greenScore: 0)
        found[0].update(
            targetDistanceKm: 5, summary: updated, previewUrl: nil, points: [RoutePoint(longitude: 3, latitude: 4)], warnings: [])
        #expect(found[0].id == route.id)
        #expect(found[0].name == "Easy Run")
        #expect(found[0].distanceKm == 5)
        #expect(found[0].points == [RoutePoint(longitude: 3, latitude: 4)])
        #expect(found[0].warnings.isEmpty)
    }
}
