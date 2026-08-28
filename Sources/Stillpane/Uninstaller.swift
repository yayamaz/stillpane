import AppKit
import ServiceManagement
import StillpaneCore

/// Reverses everything the app ever set up: the login item, the Claude Code
/// plugin and its marketplace, the captures folder, the app's defaults, the
/// permission grants, and finally the bundle itself.
///
/// Every step is best-effort and records what it could not undo, so a partial
/// uninstall - no claude binary, a file already gone - never traps the user in
/// a half-removed state. The report says exactly what is left.
@MainActor
enum Uninstaller {
    private nonisolated static let bundleID =
        Bundle.main.bundleIdentifier ?? "app.stillpane.Stillpane"

    /// `stopCaptures` runs the moment the user confirms, before any teardown:
    /// a capture starting mid-removal would recreate the capture root after
    /// it was deleted, leaving files behind a success dialog said were gone.
    /// A capture already in flight gets to finish first (`captureRunning`
    /// polls it), with no deadline of its own: every stage of the pipeline is
    /// individually bounded (screenshot 10s + kill grace, AX walk 8s with 2s
    /// per call, then a local save), so this wait terminates by construction,
    /// and a cap short enough to matter would reopen the race it closes.
    static func confirmAndRun(
        stopCaptures: () -> Void, captureRunning: @escaping @MainActor () -> Bool
    ) {
        let choice = VoidAlert.present { respond in
            UninstallConfirmView(respond: respond)
        }
        guard choice == 0 else { return }
        stopCaptures()
        Task { @MainActor in
            while captureRunning() {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            run()
        }
    }

    /// The claude subcommands block on subprocesses, so the whole teardown
    /// runs off the main thread and the report comes back to it.
    private static func run() {
        DispatchQueue.global(qos: .userInitiated).async {
            let leftovers = removeEverything()
            Task { @MainActor in finish(leftovers: leftovers) }
        }
    }

    /// Returns a human-readable line per step that failed. Runs off the main
    /// actor: everything here is subprocesses and filesystem.
    private nonisolated static func removeEverything() -> [String] {
        var leftovers: [String] = []

        if let claude = ClaudeCLI.locate() {
            if !ClaudeCLI.uninstallPlugin(claude).succeeded {
                leftovers.append("Claude Code plugin: run `claude plugin uninstall \(ClaudeCLI.pluginId)`")
            }
            if !ClaudeCLI.removeMarketplace(claude).succeeded {
                leftovers.append(
                    "Marketplace entry: run `claude plugin marketplace remove \(ClaudeCLI.marketplaceName)`")
            }
        } else {
            leftovers.append(
                "Claude Code plugin: the claude command was not found - run `claude plugin uninstall \(ClaudeCLI.pluginId)` yourself"
            )
        }

        let captures = CaptureStore.defaultRootURL
        if FileManager.default.fileExists(atPath: captures.path),
            (try? FileManager.default.removeItem(at: captures)) == nil
        {
            leftovers.append("Captures folder: delete \(captures.path) yourself")
        }

        // The grants become inert once the app is gone; resetting just keeps
        // the System Settings lists clean. `tccutil` failing (it can, per
        // policy) is not worth a leftover line.
        for service in ["Accessibility", "ScreenCapture"] {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", service, bundleID]
            if (try? reset.run()) != nil {
                _ = Subprocess.waitOrKill(reset, timeout: 10)
            }
        }

        return leftovers
    }

    private static func finish(leftovers: [String]) {
        try? SMAppService.mainApp.unregister()
        UserDefaults.standard.removePersistentDomain(forName: bundleID)

        var trashed = false
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            trashed = (try? FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)) != nil
        }

        var lines = [
            trashed ? "The app has been moved to the Trash." : "Move \(bundleURL.path) to the Trash to finish."
        ]
        if !leftovers.isEmpty {
            lines.append("")
            lines.append("A few things could not be removed automatically:")
            lines.append(contentsOf: leftovers.map { "- \($0)" })
        }
        VoidAlert.show(
            title: "stillpane is uninstalled",
            message: lines.joined(separator: "\n"),
            buttons: ["Quit"]
        )
        NSApp.terminate(nil)
    }
}
