import FoundationModels
import RouteKit

@Generable
struct GeneratedWorkout {
    @Guide(description: "The workout's steps in order, grouped into blocks.")
    var blocks: [GeneratedBlock]
}

@Generable
struct GeneratedBlock {
    @Guide(description: "How many times the block repeats; 1 for a step done once.", .range(1...50))
    var repeats: Int
    @Guide(
        description:
            "One entry per step, worded as on the screen, e.g. `5 mins walking warm up`, `60s at a conversational pace` or `1.25km at a conversational pace`."
    )
    var steps: [String]
}

/// Rewrites recognised workout text into Notes-style lines with the on-device model.
enum WorkoutRewriter {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }

    private static let instructions = """
        You read the recognised text of a Runna running-workout screen. Keep only the workout's steps: the \
        warm-up, the main steps and the cool-down. Ignore app chrome (buttons, tabs, the status bar, coach \
        cards) and any completed-activity statistics. A `Repeat xN` group is one block with N repeats and one \
        step per row; every other step is its own block with 1 repeat. Copy each step's numbers, units and \
        wording exactly as written, correcting only obvious recognition mistakes such as `O` for `0`. Never \
        invent, merge or drop steps.
        """

    /// The rewritten text, or `nil` when the model can't help.
    static func rewrite(lines: [String]) async -> String? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        guard let response = try? await session.respond(to: prompt, generating: GeneratedWorkout.self) else {
            return nil
        }
        let outline = WorkoutOutline(
            title: "", blocks: response.content.blocks.map { .init(repeats: $0.repeats, steps: $0.steps) })
        let text = outline.notesText
        return text.isEmpty ? nil : text
    }
}
