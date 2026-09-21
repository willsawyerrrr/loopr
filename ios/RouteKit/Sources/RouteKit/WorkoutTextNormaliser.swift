import Foundation

/// A Runna workout screen read into the text `POST /api/route` parses, plus what the screen states about it.
public struct RecognisedWorkout: Hashable, Sendable {
    /// Notes-style workout text; the screen's own header is not part of it.
    public var text: String
    /// The workout type from the `Type • Nkm` line, for naming the route.
    public var title: String?
    /// The running distance in that line. The app counts only the running, not the walking between,
    /// so it can't be checked by the server, which compares it with the whole workout.
    public var statedRunKm: Double?
}

public enum WorkoutText {
    /// Reads OCR `lines` of a workout screen, or of Notes-style text.
    ///
    /// On the screen only the steps between the `Description` heading and the `Start Workout` button are
    /// kept, laid out as the Notes are: blocks separated by a blank line and each `Repeat xN` block as
    /// `N reps of:` with one bullet per step. Chrome, step numbers, `WALK` / `RUN` labels and info glyphs
    /// are dropped, common OCR confusions fixed and wrapped lines joined.
    public static func read(_ lines: [String]) -> RecognisedWorkout {
        let cleaned = lines.map(cleanLine)
        let heading = cleaned.firstIndex { $0.wholeMatch(of: /(?i)description/) != nil }
        var title: String?
        var statedRunKm: Double?
        for line in cleaned[..<(heading ?? 0)] {
            if let match = line.wholeMatch(of: /(.+?)\s*•\s*(\d+(?:\.\d+)?)km/) {
                title = String(match.1)
                statedRunKm = Double(match.2)
                break
            }
        }
        var region = Array(cleaned[(heading.map { $0 + 1 } ?? 0)...])
        if let stop = region.firstIndex(where: { $0.firstMatch(of: endOfSteps) != nil }) {
            region = Array(region[..<stop])
        }
        let steps = joinWrapped(region.compactMap(stripDecorations).filter { !isChrome($0) || $0.isEmpty })
        return RecognisedWorkout(text: layout(steps), title: title, statedRunKm: statedRunKm)
    }

    /// The Notes-style text alone; see `read(_:)`.
    public static func normalise(_ lines: [String]) -> String { read(lines).text }

    /// A `WALK` / `RUN` / `REST` badge, with the icon's stray glyph the OCR may put in front of it.
    static func isActivityLabel(_ text: String) -> Bool {
        text.wholeMatch(of: /(?i)[^A-Za-z0-9]{0,3}\s*(?:walk|run|rest)/) != nil
    }

    // MARK: Per-line cleanup

    private static func cleanLine(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return "" }
        line = line.replacing(/[·∙●○◦▪‣]/, with: "•")
        line = line.replacing(/^[*»›+]\s+/, with: "• ")
        line = line.replacing(/^[-–—]\s+(?=[0-9A-Za-z])/, with: "• ")
        line = line.replacing(/^•\s*/, with: "• ")
        return line.replacing(/\s+/, with: " ")
    }

    /// Removes what the app draws beside a step and fixes what the OCR misreads in it.
    /// Returns `nil` for lines that are only decoration.
    private static func stripDecorations(_ line: String) -> String? {
        var line = line
        guard !line.isEmpty else { return "" }
        if isActivityLabel(line) || line.wholeMatch(of: /\d{1,2}/) != nil { return nil }
        // A label or info glyph that shared the step's row.
        line = line.replacing(/\s+[^A-Za-z0-9\s]{0,2}\s*(?:WALK|RUN|REST)$/, with: "")
        if line.contains(where: \.isNumber) { line = line.replacing(/\s+(?:[Oo0iI©®ⓘ①]|\([iI]\))$/, with: "") }
        // A step number that shared the step's row.
        line = line.replacing(/^[1-9]\s+(?=\d+(?:\.\d+)?\s*(?i:km|m|s|mins?)\b)/, with: "")
        line = fixDigits(line)
        line = fixUnits(line)
        line = line.replacing(/(?i)^[^A-Za-z0-9]{0,3}\s*repeat\s*[x×]\s*(\d+)$/, with: { "\($0.1) reps of:" })
        line = line.replacing(/(?i)^[^A-Za-z0-9]{0,3}\s*repeat\s*(\d+)\s*[x×]$/, with: { "\($0.1) reps of:" })
        line = line.replacing(/(?i)^(\d+)\s*reps?\s+of\b\s*:?$/, with: { "\($0.1) reps of:" })
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// `O`/`o` to `0` and `I`/`l`/`|` to `1` inside numbers that read as quantities.
    private static func fixDigits(_ line: String) -> String {
        var line = line.replacing(
            /(^|[^A-Za-z0-9])([0-9OoIl|.]*[0-9][0-9OoIl|.]*)(?=\s*(?i:km|m|s|secs?|mins?|minutes?)\b)/
        ) { match in
            match.1 + String(match.2.map { "Oo".contains($0) ? "0" : "Il|".contains($0) ? "1" : $0 })
        }
        line = line.replacing(/(\d{1,2}):([0-9OoIlSs]{2})(?=\s*\/\s*km)/) { match in
            let seconds = String(
                match.2.map { "Oo".contains($0) ? "0" : "Il".contains($0) ? "1" : "Ss".contains($0) ? "5" : $0 })
            return "\(match.1):\(seconds)"
        }
        return line
    }

    /// Unspaces units, standardises seconds, minutes and pace notation, and reads `2,5km` as 2.5 km.
    private static func fixUnits(_ line: String) -> String {
        var line = line
        line = line.replacing(/(\d),(\d)(?=\s*(?i:km)\b)/, with: { "\($0.1).\($0.2)" })
        line = line.replacing(/(\d)\s*(?i:km)\b/, with: { "\($0.1)km" })
        line = line.replacing(/(\d)\s*(?i:secs?|seconds?)\b/, with: { "\($0.1)s" })
        line = line.replacing(/(\d)\s*(?:s|S)\b/, with: { "\($0.1)s" })
        line = line.replacing(/(\d)\s*(?:m|M)\b/, with: { "\($0.1)m" })
        line = line.replacing(/(\d)\s*(?i:mins?|minutes?)\b/, with: { "\($0.1) mins" })
        line = line.replacing(/(\d:\d{2})\s*\/\s*(?i:km)\b/, with: { "\($0.1)/km" })
        return line
    }

    // MARK: Chrome

    /// Where the steps end: the button below them, or the coach's card.
    nonisolated(unsafe) private static let endOfSteps = /(?i)^(?:start workout|head coach)\b/

    private static let chromeLines: Set<String> = [
        "start", "start workout", "add route", "add a route", "link activity", "skip workout", "warm-up stretches",
        "edit", "share", "done", "close", "back", "cancel", "home", "plan", "training", "progress", "explore",
        "profile", "stats", "community", "more", "menu", "workout details", "today", "tomorrow",
    ]

    private static func isChrome(_ line: String) -> Bool {
        chromeLines.contains(line.lowercased()) || line.wholeMatch(of: /\d{1,3}%|\d{1,2}:\d{2}/) != nil
    }

    // MARK: Wrapped lines

    nonisolated(unsafe) private static let connective = /(?i)(?:\b(?:at|a|an|the|of|and|to|for|then|with)|,)$/
    nonisolated(unsafe) private static let sectionHeader = /(?i)^[^A-Za-z0-9]{0,3}\s*(?:warm[-\s]?up|session|cool[-\s]?down)\s*:?$/
    nonisolated(unsafe) private static let repeatMarker = /^\d+ reps of:$/

    private static func startsNewItem(_ line: String) -> Bool {
        line.hasPrefix("•") || line.wholeMatch(of: sectionHeader) != nil || line.wholeMatch(of: repeatMarker) != nil
    }

    /// Joins a line onto its predecessor when it continues it: a dangling connective or comma, or a lowercase start.
    private static func joinWrapped(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            guard let previous = result.last, !previous.isEmpty, !line.isEmpty, !startsNewItem(line),
                !previous.hasSuffix(":"), !startsNewItem(previous)
            else {
                result.append(line)
                continue
            }
            if previous.firstMatch(of: connective) != nil || line.first?.isLowercase == true {
                result[result.count - 1] = previous + " " + line
            } else {
                result.append(line)
            }
        }
        return result
    }

    // MARK: Layout

    nonisolated(unsafe) private static let hasQuantity = /\d\s*(?:km|m|s|mins?)\b/

    /// Blocks are separated by a blank line, and a block after a `N reps of:` marker is bulleted until the
    /// next section header, marker or blank line so the server repeats each of its steps.
    private static func layout(_ lines: [String]) -> String {
        var output: [String] = []
        var breakPending = false
        var inRepeat = false
        for line in lines {
            if line.isEmpty || line.wholeMatch(of: sectionHeader) != nil {
                breakPending = true
                inRepeat = false
                continue
            }
            let isMarker = line.wholeMatch(of: repeatMarker) != nil
            if isMarker { breakPending = true }
            if breakPending, !output.isEmpty { output.append("") }
            breakPending = false
            inRepeat = isMarker || inRepeat
            if inRepeat, !isMarker, !line.hasPrefix("•"), line.firstMatch(of: hasQuantity) != nil {
                output.append("• " + line)
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }
}
