import Foundation

/// A workout as structured steps, rendered to the Notes-style text the server parses.
public struct WorkoutOutline: Hashable, Sendable {
    public struct Block: Hashable, Sendable {
        /// How many times the steps repeat; `1` for a single pass.
        public var repeats: Int
        /// e.g. `60s at a conversational pace, 30s walking`.
        public var steps: [String]

        public init(repeats: Int, steps: [String]) {
            self.repeats = repeats
            self.steps = steps
        }
    }

    /// e.g. `Walk Run • 29m • 29m`; empty when the workout shows no header.
    public var title: String
    public var blocks: [Block]

    public init(title: String, blocks: [Block]) {
        self.title = title
        self.blocks = blocks
    }

    /// Blocks are separated by blank lines; a repeated block becomes `N reps of:` with bulleted steps.
    public var notesText: String {
        var sections: [String] = []
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { sections.append(title) }
        for block in blocks {
            let steps = block.steps.map(Self.stripBullet).filter { !$0.isEmpty }
            guard !steps.isEmpty else { continue }
            if block.repeats > 1 {
                sections.append((["\(block.repeats) reps of:"] + steps.map { "• \($0)" }).joined(separator: "\n"))
            } else {
                sections.append(steps.joined(separator: "\n"))
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private static func stripBullet(_ step: String) -> String {
        step.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/^[•·\-*]\s*/, with: "")
    }
}
