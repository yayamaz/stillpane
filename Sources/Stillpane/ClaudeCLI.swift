import Foundation
import StillpaneCore

/// Locates the `claude` binary and drives the two plugin install commands.
///
/// A bundled app launched from Finder inherits a minimal PATH, so `command -v`
/// alone would fail for most users. The known install locations are checked
/// first, and the login-shell fallback is what picks up a PATH set in the
/// user's shell profile.
///
/// Every function here blocks on a subprocess. Call them from a background
/// queue only.
enum ClaudeCLI {
    static let repoSlug = "yayamaz/stillpane"

    /// The full plugin@marketplace id. `plugin update` in particular rejects
    /// the bare plugin name, so every subcommand gets the full form.
    static let pluginId = "stillpane@stillpane"

    /// The name `plugin marketplace add` registered - the part after the @.
    static let marketplaceName = "stillpane"

    static let installCommands = """
        /plugin marketplace add \(repoSlug)
        /plugin install \(pluginId)
        """

    /// A prompting or wedged subcommand must not hang the setup window.
    private static let timeout: TimeInterval = 60

    struct Output {
        let succeeded: Bool
        let standardOutput: String
        let standardError: String

        /// One line fit for showing a user. Diagnostics land on stderr, so
        /// prefer it and fall back to stdout.
        var failureMessage: String {
            let error = lastLine(standardError)
            if !error.isEmpty { return error }
            let output = lastLine(standardOutput)
            return output.isEmpty ? "no output" : output
        }
    }

    /// `~/.local/bin` is the current installer default, so it goes first.
    private static let knownPaths = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    static func locate() -> URL? {
        for path in knownPaths {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        // `command -v` rather than `which`: shims installed as shell functions
        // make `which` print the function body instead of a path. Only stdout
        // is parsed, because a login shell writes profile noise to stderr.
        let shell = run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v claude"])
        let path = lastLine(shell.standardOutput)
        guard shell.succeeded, !path.isEmpty,
            FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// True when `claude plugin list --json` lists our plugin. A non-zero
    /// exit, an older CLI without the subcommand, or a missing binary all read
    /// as "not installed", which is the safe direction: the worst case is
    /// offering an install the user does not need, and install itself is
    /// idempotent.
    static func isPluginInstalled(_ claude: URL) -> Bool {
        installedPluginVersion(claude) != nil
    }

    /// The installed plugin's version, or nil when it is not installed or the
    /// listing cannot be read.
    static func installedPluginVersion(_ claude: URL) -> String? {
        let result = run(claude, ["plugin", "list", "--json"])
        guard result.succeeded,
            let data = result.standardOutput.data(using: .utf8),
            let plugins = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return plugins.first { ($0["id"] as? String) == pluginId }?["version"] as? String
    }

    struct Detection: Sendable {
        let path: URL?
        let pluginInstalled: Bool
    }

    /// Locating spawns a login shell and detection spawns the CLI itself, so
    /// both run off the main thread: neither belongs on the launch path.
    static func detectInBackground(completion: @escaping @MainActor (Detection) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let path = locate()
            let detection = Detection(
                path: path, pluginInstalled: path.map(isPluginInstalled) ?? false
            )
            Task { @MainActor in completion(detection) }
        }
    }

    /// Removes the installed plugin. The plugin goes before the marketplace:
    /// removing the marketplace first would orphan the install.
    static func uninstallPlugin(_ claude: URL) -> Output {
        run(claude, ["plugin", "uninstall", pluginId])
    }

    /// Removes the marketplace registration.
    static func removeMarketplace(_ claude: URL) -> Output {
        run(claude, ["plugin", "marketplace", "remove", marketplaceName])
    }

    /// Adds the marketplace, then installs the plugin. Stops at the first
    /// failure and returns its output.
    static func installPlugin(_ claude: URL) -> Output {
        let marketplace = run(claude, ["plugin", "marketplace", "add", repoSlug])
        guard marketplace.succeeded else { return marketplace }
        return run(claude, ["plugin", "install", pluginId])
    }

    static func run(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval = ClaudeCLI.timeout
    ) -> Output {
        run(executable, arguments, environment: environment(for: executable), timeout: timeout)
    }

    private static func run(
        _ executable: URL, _ arguments: [String], environment: [String: String],
        timeout: TimeInterval = ClaudeCLI.timeout
    ) -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // A subcommand that decides to prompt would otherwise wait on a
        // terminal that does not exist and hang until the timeout.
        process.standardInput = FileHandle.nullDevice

        let outURL = temporaryFile()
        let errURL = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }
        // Files rather than pipes: a pipe whose buffer fills while we wait on
        // the other one deadlocks the child, and draining two pipes
        // concurrently buys nothing here.
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        guard let outHandle = try? FileHandle(forWritingTo: outURL),
            let errHandle = try? FileHandle(forWritingTo: errURL)
        else {
            return Output(succeeded: false, standardOutput: "", standardError: "no scratch space")
        }
        defer {
            try? outHandle.close()
            try? errHandle.close()
        }
        process.standardOutput = outHandle
        process.standardError = errHandle

        do {
            try process.run()
        } catch {
            return Output(
                succeeded: false, standardOutput: "", standardError: error.localizedDescription
            )
        }

        let timedOut = !Subprocess.waitOrKill(process, timeout: timeout)

        let standardOutput = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        var standardError = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        if timedOut {
            standardError = "Timed out after \(Int(timeout)) seconds."
        }
        return Output(
            succeeded: !timedOut && process.terminationStatus == 0,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    /// An npm-installed `claude` starts with `#!/usr/bin/env node`, which fails
    /// with "env: node: No such file or directory" under the bundle's minimal
    /// PATH. Put the binary's own directory first, since a version manager
    /// keeps node beside it.
    private static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let prefixes = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        environment["PATH"] = (prefixes + [inherited]).joined(separator: ":")
        if environment["CLAUDE_CONFIG_DIR"] == nil, let configDir = configDirOverride {
            environment["CLAUDE_CONFIG_DIR"] = configDir
        }
        return environment
    }

    /// The user's CLAUDE_CONFIG_DIR, read once from a login shell. Relocating
    /// Claude Code's config folder is done with an export in a shell profile,
    /// which a Finder-launched app never inherits - and a plugin install that
    /// misses it lands in a default ~/.claude that user's claude never reads,
    /// while the assistant reports success. The sentinel prefix keeps profile
    /// noise on stdout from being mistaken for a value; an empty or missing
    /// value means the default location, so nothing is passed.
    private static let configDirOverride: String? = {
        let sentinel = "stillpane-config-dir:"
        let shell = run(
            URL(fileURLWithPath: "/bin/zsh"),
            ["-lc", "printf '\(sentinel)%s\\n' \"${CLAUDE_CONFIG_DIR:-}\""],
            environment: ProcessInfo.processInfo.environment
        )
        guard shell.succeeded else { return nil }
        let value = shell.standardOutput
            .split(separator: "\n")
            .last { $0.hasPrefix(sentinel) }
            .map { $0.dropFirst(sentinel.count).trimmingCharacters(in: .whitespaces) }
        guard let value, !value.isEmpty else { return nil }
        return value
    }()

    private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stillpane-cli-\(UUID().uuidString)")
    }

    private static func lastLine(_ text: String) -> String {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
    }
}
