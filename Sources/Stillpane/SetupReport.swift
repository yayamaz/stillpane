import AppKit
import StillpaneCore

/// One line of the setup diagnosis: a named link in the chain, its state in
/// words, a health reading the UI can color, and the setup step that repairs
/// it. `step` is nil for a row nothing can be done about from here, which is
/// what makes it unclickable on the status board.
struct SetupItem {
    enum Health { case ok, warn, fail, info }
    let name: String
    let detail: String
    let health: Health
    var step: OnboardingStep?
}

/// Assembles the diagnostics behind the setup status board and every "report
/// a problem" surface, and opens the prefilled GitHub issue. One assembly
/// means what the user sees is exactly what a maintainer gets, wherever the
/// report started - the board, the menu, or an onboarding failure.
@MainActor
enum SetupReport {
    /// Gathers the full report off the main thread (the Claude checks spawn
    /// subprocesses) and hands it back on it.
    static func gather(
        accessibilityStatus: String, completion: @escaping @MainActor (String) -> Void
    ) {
        gatherItems(accessibilityStatus: accessibilityStatus) { items in
            completion(text(from: items))
        }
    }

    static func gatherItems(
        accessibilityStatus: String, completion: @escaping @MainActor ([SetupItem]) -> Void
    ) {
        let accessibility = SetupItem(
            name: "Accessibility",
            detail: accessibilityStatus,
            health: accessibilityStatus == "granted"
                ? .ok
                : accessibilityStatus.contains("granted") ? .warn : .fail,
            step: .accessibility
        )
        let screenRecording: SetupItem =
            if Permissions.screenRecordingGranted {
                SetupItem(
                    name: "Screen Recording", detail: "granted", health: .ok,
                    step: .screenRecording
                )
            } else if OnboardingState.screenRecordingSkipped {
                SetupItem(
                    name: "Screen Recording",
                    detail: "off by choice - captures carry text only", health: .info,
                    step: .screenRecording
                )
            } else {
                SetupItem(
                    name: "Screen Recording",
                    detail: "not granted - captures carry text only", health: .warn,
                    step: .screenRecording
                )
            }
        DispatchQueue.global(qos: .userInitiated).async {
            let claude = ClaudeCLI.locate()
            let pluginVersion = claude.flatMap(ClaudeCLI.installedPluginVersion)
            let claudeItem: SetupItem
            let pluginItem: SetupItem
            if let claude {
                claudeItem = SetupItem(
                    name: "claude command", detail: claude.path, health: .ok, step: .claudeCode
                )
                // The app never updates the plugin; when the install is older
                // than the version this app shipped with, the row hands the
                // user the explicit command instead. Equal or newer is
                // healthy.
                pluginItem =
                    pluginVersion.map { installed in
                        UpdateFeed.isNewer(StillpaneVersion.expectedPluginVersion, than: installed)
                            ? SetupItem(
                                name: "Claude Code plugin",
                                detail:
                                    "installed (\(installed)), \(StillpaneVersion.expectedPluginVersion) available - run: claude plugin update \(ClaudeCLI.pluginId)",
                                health: .warn, step: .claudeCode
                            )
                            : SetupItem(
                                name: "Claude Code plugin", detail: "installed (\(installed))",
                                health: .ok, step: .claudeCode
                            )
                    }
                    ?? SetupItem(
                        name: "Claude Code plugin",
                        detail: "not installed - the Setup Assistant installs it", health: .fail,
                        step: .claudeCode
                    )
            } else {
                claudeItem = SetupItem(
                    name: "claude command", detail: "not found", health: .fail, step: .claudeCode
                )
                pluginItem = SetupItem(
                    name: "Claude Code plugin",
                    detail: "cannot check without the claude command", health: .warn, step: .claudeCode
                )
            }
            let items = [
                accessibility, screenRecording, claudeItem, pluginItem, latestCaptureItem(),
            ]
            Task { @MainActor in completion(items) }
        }
    }

    /// Opens a GitHub issue form with the report already in the body, so
    /// every report arrives debuggable. `detail` carries whatever error
    /// message prompted the report.
    static func openIssue(report: String, detail: String? = nil) {
        var body = "<describe the problem here>\n"
        if let detail {
            body += "\nWhat failed: \(detail)\n"
        }
        body += "\n---\n\(report)"
        guard
            let url = SupportLink.newIssueURL(
                repoSlug: ClaudeCLI.repoSlug, title: "", body: body
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated static func text(from items: [SetupItem]) -> String {
        let lines = items.map { "\($0.name): \($0.detail)" }
        return """
            stillpane \(StillpaneVersion.version) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            \(lines.joined(separator: "\n"))
            """
    }

    nonisolated static func latestCaptureItem() -> SetupItem {
        guard let latest = latestCapture() else {
            return SetupItem(name: "Latest capture", detail: "none yet", health: .info)
        }
        if latest.delivered {
            return SetupItem(
                name: "Latest capture", detail: "attached to a Claude Code message", health: .ok
            )
        }
        if latest.age <= 120 {
            return SetupItem(
                name: "Latest capture", detail: "waiting to attach to your next message",
                health: .info
            )
        }
        return SetupItem(
            name: "Latest capture", detail: "missed the 2-minute window - /stillpane brings it in",
            health: .warn
        )
    }

    /// Mirrors the hook's own decisions (newest directory by name, .delivered
    /// sentinel, 2-minute window measured from context.md, which is written
    /// once at capture time and never touched again) so the report describes
    /// what the hook actually did, not a guess. Shared with AppDelegate's
    /// missed-delivery notice for the same reason.
    nonisolated static func latestCapture() -> (name: String, delivered: Bool, age: TimeInterval)? {
        let fileManager = FileManager.default
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: CaptureStore.defaultRootURL, includingPropertiesForKeys: []
            ),
            let latest = entries.filter({
                $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("20")
            }).max(by: { $0.lastPathComponent < $1.lastPathComponent })
        else { return nil }
        let delivered = fileManager.fileExists(
            atPath: latest.appendingPathComponent(".delivered").path
        )
        let written =
            (try? latest.appendingPathComponent("context.md")
            .resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return (latest.lastPathComponent, delivered, Date().timeIntervalSince(written))
    }
}
