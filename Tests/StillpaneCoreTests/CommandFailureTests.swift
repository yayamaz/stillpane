import Testing

@testable import StillpaneCore

@Suite("CommandFailure")
struct CommandFailureTests {
    /// The shape `claude plugin marketplace add` produces when git cannot
    /// reach the repository over SSH.
    private let sshFailure = """
        ✘ Failed to add marketplace: Failed to clone marketplace repository: Cloning into '/Users/me/.claude/plugins/marketplaces/yayamaz-stillpane'...
        git@github.com: Permission denied (publickey).
        fatal: Could not read from remote repository.

        Please make sure you have the correct access rights
        and the repository exists.

        """

    @Test func gitVerdictWinsOverTheFragmentAfterIt() {
        #expect(
            CommandFailure.summary(standardError: sshFailure, standardOutput: "Adding marketplace…")
                == "Could not read from remote repository."
        )
    }

    @Test func cliSummaryWhenGitPrintsNoVerdict() {
        let stderr = "✘ Failed to add marketplace: Timed out after 60 seconds.\n"
        #expect(
            CommandFailure.summary(standardError: stderr, standardOutput: "")
                == "Failed to add marketplace: Timed out after 60 seconds."
        )
    }

    @Test func lastLineWhenNothingIsMarked() {
        #expect(
            CommandFailure.summary(standardError: "  \nsomething broke\n\n", standardOutput: "")
                == "something broke"
        )
    }

    @Test func stdoutOnlyWhenStderrIsEmpty() {
        #expect(CommandFailure.summary(standardError: "\n", standardOutput: "fatal: on stdout\n") == "on stdout")
        #expect(CommandFailure.summary(standardError: "", standardOutput: "") == "no output")
    }

    @Test func transcriptLabelsStreamsAndSkipsEmptyOnes() {
        #expect(
            CommandFailure.transcript(standardError: "bad\n", standardOutput: "", limit: 100)
                == "[stderr]\nbad"
        )
        #expect(
            CommandFailure.transcript(standardError: "bad\n", standardOutput: "step 1\n", limit: 100)
                == "[stderr]\nbad\n\n[stdout]\nstep 1"
        )
    }

    @Test func transcriptKeepsTheTailWhenOverLimit() {
        let transcript = CommandFailure.transcript(
            standardError: "progress\nprogress\nfatal: the end", standardOutput: "", limit: 14
        )
        #expect(transcript == "[...]\nfatal: the end")
    }
}
