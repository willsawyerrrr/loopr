import Foundation
import RouteKit

/// What the screenshot flows share: how a recognised workout becomes a route request.
enum ScreenshotRouting {
    /// A pipeline using the app's hills, green and pace settings. With `rewriting`, a distance that
    /// doesn't check out is retried once on the on-device model's rewrite of those OCR lines.
    /// `budget` bounds the whole run, for intents.
    static func pipeline(
        rewriting lines: [String]?, budget: Duration? = nil, timeout: TimeInterval = 60
    ) -> ScreenshotRoutePipeline {
        let defaults = UserDefaults.standard
        var rewrite: ScreenshotRoutePipeline.Rewriter?
        if let lines, WorkoutRewriter.isAvailable {
            rewrite = { _ in await WorkoutRewriter.rewrite(lines: lines) }
        }
        return ScreenshotRoutePipeline(
            service: RouteService(timeout: timeout),
            hillsPreference: defaults.double(forKey: "hillsPreference"),
            greenPreference: defaults.double(forKey: "greenPreference"),
            paces: PaceStore().paces,
            rewrite: rewrite,
            budget: budget
        )
    }

    static var today: String { RunPlan.dateString(.now) }
}
