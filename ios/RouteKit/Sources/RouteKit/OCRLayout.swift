import Foundation

/// A run of recognised text with its position in the image, in `0...1` with the origin at the top left.
public struct OCRFragment: Hashable, Sendable {
    public var text: String
    public var minX: Double
    public var midY: Double
    public var height: Double

    public init(text: String, minX: Double, midY: Double, height: Double) {
        self.text = text
        self.minX = minX
        self.midY = midY
        self.height = height
    }
}

public enum OCRLayout {
    /// Reading-order lines: fragments on one row are joined left to right. The step numbers in the
    /// left gutter and the `WALK` / `RUN` labels at the right of each step are dropped first, since
    /// they share a row with the step text.
    public static func lines(from fragments: [OCRFragment]) -> [String] {
        var rows: [Row] = []
        let kept = fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && !isGutterOrLabel($0) }
        for fragment in kept.sorted(by: { $0.midY < $1.midY }) {
            if var last = rows.last, abs(fragment.midY - last.midY) < 0.5 * min(fragment.height, last.height) {
                last.fragments.append(fragment)
                rows[rows.count - 1] = last
            } else {
                rows.append(Row(fragments: [fragment]))
            }
        }
        return rows.map(\.text)
    }

    private struct Row {
        var fragments: [OCRFragment]
        var midY: Double { fragments.map(\.midY).reduce(0, +) / Double(fragments.count) }
        var height: Double { fragments.map(\.height).max() ?? 0 }
        var text: String { fragments.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
    }

    private static func isGutterOrLabel(_ fragment: OCRFragment) -> Bool {
        let text = fragment.text.trimmingCharacters(in: .whitespaces)
        if fragment.minX < 0.2, text.wholeMatch(of: /\d{1,2}/) != nil { return true }
        return WorkoutText.isActivityLabel(text)
    }
}
