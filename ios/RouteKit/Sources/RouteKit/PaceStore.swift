import Foundation

/// The pace table (Runna pace phrase to minutes per km) sent with each workout request.
public struct PaceStore: @unchecked Sendable {
    /// Mirrors `DEFAULT_PACES` in `src/config.ts`.
    public static let defaults: [String: Double] = [
        "walking": 11.0,
        "conversational pace": 7.5,
    ]

    private let defaults: UserDefaults
    private let key = "paces"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved table, or the defaults when nothing has been saved.
    public var paces: [String: Double] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }
            ?? Self.defaults
    }

    /// Saves `paces` with trimmed, lowercased phrases, dropping blank phrases and non-positive paces.
    public func save(_ paces: [String: Double]) {
        var cleaned: [String: Double] = [:]
        for (phrase, pace) in paces {
            let key = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty, pace > 0, pace.isFinite { cleaned[key] = pace }
        }
        defaults.set(try? JSONEncoder().encode(cleaned), forKey: key)
    }
}
