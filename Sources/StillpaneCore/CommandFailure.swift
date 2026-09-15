import Foundation

/// Reads a failed command's output for the one line worth showing and the
/// transcript worth reporting.
public enum CommandFailure {
    /// The line that states what went wrong. Claude Code's plugin commands
    /// print their own summary of a failure, but a git failure inside it
    /// arrives as git's whole stderr, where the verdict is the `fatal:` line
    /// and the lines after it are explanation. The last line of such a
    /// message is a sentence fragment, so it is only the fallback.
    ///
    /// Diagnostics land on stderr, so it is read first; stdout is only
    /// consulted when stderr says nothing.
    public static func summary(standardError: String, standardOutput: String) -> String {
        for text in [standardError, standardOutput] {
            let lines = text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let verdict = lines.first(where: { $0.hasPrefix("fatal:") }) {
                return verdict.dropFirst("fatal:".count).trimmingCharacters(in: .whitespaces)
            }
            if let summary = lines.first(where: { $0.hasPrefix("✘") }) {
                return summary.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            if let last = lines.last { return last }
        }
        return "no output"
    }

    /// Both streams of a failed command, labelled, for a report body. When
    /// the whole exceeds `limit` the head is dropped: a command's verdict
    /// comes after its progress, so the tail is the part worth keeping.
    public static func transcript(standardError: String, standardOutput: String, limit: Int) -> String {
        var sections: [String] = []
        for (label, text) in [("stderr", standardError), ("stdout", standardOutput)] {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sections.append("[\(label)]\n\(trimmed)") }
        }
        let whole = sections.joined(separator: "\n\n")
        guard whole.count > limit else { return whole }
        return "[...]\n" + whole.suffix(limit)
    }
}
