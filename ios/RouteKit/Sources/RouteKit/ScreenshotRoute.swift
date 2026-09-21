import Foundation

/// A route generated from a workout screenshot.
public struct ScreenshotRoute: Sendable {
    public var response: RouteResponse
    /// The workout text that produced it.
    public var text: String
    /// Whether the on-device model had to rewrite the recognised text first.
    public var rewritten: Bool
    /// Whether the total was checked against a figure on the screen.
    public var crossChecked: Bool
}

/// The workout couldn't be turned into a trustworthy distance.
public struct ManualDistanceRequest: Sendable {
    /// The recognised text, for the user to correct.
    public var text: String
    /// What went wrong, verbatim from the checks and the server.
    public var problems: [String]
    /// A distance to prefill, when one is known.
    public var suggestedKm: Double?
}

public enum ScreenshotRouteOutcome: Sendable {
    case route(ScreenshotRoute)
    case needsManualDistance(ManualDistanceRequest)
}

/// Sends recognised workout text to the server and accepts the route only when its distance checks out.
///
/// The distance must agree with the workout's own header (the server's `checksum`) and with the running
/// distance stated on the screen. When it doesn't, the text is rewritten once by `rewrite` and retried;
/// if that doesn't help either, the caller is asked for a distance instead.
public struct ScreenshotRoutePipeline: Sendable {
    public typealias Rewriter = @Sendable (String) async -> String?

    /// The least time worth spending on a rewrite and a second request.
    private static let minimumRetryBudget: Duration = .seconds(8)

    public var service: RouteService
    public var hillsPreference: Double
    public var greenPreference: Double
    public var paces: [String: Double]
    public var rewrite: Rewriter?
    /// Total wall-clock allowance across requests and the rewrite; each request is also capped by what remains.
    public var budget: Duration?

    public init(
        service: RouteService = RouteService(),
        hillsPreference: Double = 0,
        greenPreference: Double = 0,
        paces: [String: Double] = [:],
        rewrite: Rewriter? = nil,
        budget: Duration? = nil
    ) {
        self.service = service
        self.hillsPreference = hillsPreference
        self.greenPreference = greenPreference
        self.paces = paces
        self.rewrite = rewrite
        self.budget = budget
    }

    private enum Attempt {
        case accepted(RouteResponse, crossChecked: Bool)
        case rejected(problems: [String], suggestedKm: Double?)
    }

    public func route(
        for workout: RecognisedWorkout, start: RoutePoint, date: String
    ) async throws -> ScreenshotRouteOutcome {
        let clock = ContinuousClock()
        let deadline = budget.map { clock.now + $0 }
        let title = workout.title ?? "Runna workout"

        let first = try await attempt(workout.text, title, date, start, statedRunKm: workout.statedRunKm, deadline)
        guard case .rejected(let problems, let suggestedKm) = first else {
            return accepted(first, text: workout.text, rewritten: false)!
        }
        let canRetry = { deadline.map { clock.now.duration(to: $0) >= Self.minimumRetryBudget } ?? true }
        if let rewrite, canRetry(), let rewritten = await rewrite(workout.text), rewritten != workout.text, canRetry() {
            let second = try await attempt(rewritten, title, date, start, statedRunKm: workout.statedRunKm, deadline)
            if let route = accepted(second, text: rewritten, rewritten: true) { return route }
        }
        return .needsManualDistance(
            ManualDistanceRequest(text: workout.text, problems: problems, suggestedKm: suggestedKm))
    }

    private func accepted(_ attempt: Attempt, text: String, rewritten: Bool) -> ScreenshotRouteOutcome? {
        guard case .accepted(let response, let crossChecked) = attempt else { return nil }
        return .route(ScreenshotRoute(response: response, text: text, rewritten: rewritten, crossChecked: crossChecked))
    }

    private func attempt(
        _ text: String, _ title: String, _ date: String, _ start: RoutePoint,
        statedRunKm: Double?, _ deadline: ContinuousClock.Instant?
    ) async throws -> Attempt {
        let request = RouteRequest(
            workout: text, title: title, date: date, start: start,
            hillsPreference: hillsPreference, greenPreference: greenPreference, paces: paces)
        var timeout: TimeInterval?
        if let deadline {
            let remaining = ContinuousClock().now.duration(to: deadline)
            timeout = max(1, Double(remaining.components.seconds))
        }
        let response: RouteResponse
        do {
            response = try await service.generate(request, timeout: timeout)
        } catch RouteServiceError.server(422, let message, let detail) {
            return .rejected(problems: [message] + (detail.map { [$0] } ?? []), suggestedKm: nil)
        }
        if let problem = response.checksum?.problem {
            return .rejected(problems: [problem] + response.warnings, suggestedKm: response.checksum?.suggestedKm)
        }
        if let stated = statedRunKm, let run = response.runKm {
            let format = { (km: Double) in km.formatted(.number.precision(.fractionLength(0...2))) }
            guard abs(run - stated) <= max(0.3, 0.1 * stated) else {
                let problem = "The screen shows \(format(stated)) km of running but the steps add up to \(format(run)) km."
                return .rejected(problems: [problem] + response.warnings, suggestedKm: response.targetDistanceKm)
            }
            return .accepted(response, crossChecked: true)
        }
        return .accepted(response, crossChecked: response.checksum?.hasStatedFigure == true)
    }
}
