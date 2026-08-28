import AppKit
import StillpaneCore

/// Offers to move a copy running outside /Applications there.
///
/// A bundle launched from ~/Downloads runs Gatekeeper-translocated on a
/// randomized read-only mount, and any out-of-place copy makes trouble later:
/// the relaunch flows and the login item point at a path that stops existing,
/// and the uninstaller cannot trash a read-only bundle. /Applications is the
/// one stable home every Mac has.
@MainActor
enum AppPlacement {
    private static let destination = URL(fileURLWithPath: "/Applications/stillpane.app")

    /// Returns true when a move was accepted and worked: a fresh copy is
    /// launching from /Applications and this process is terminating. The user
    /// declining, or the move failing, returns false and the app runs on from
    /// where it is - out of place beats not running.
    static func moveToApplicationsIfNeeded() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        // A bare debug binary has no bundle to move.
        guard bundleURL.pathExtension == "app" else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for placed in ["/Applications/", home + "/Applications/"]
        where bundleURL.path.hasPrefix(placed) { return false }

        NSApp.activate(ignoringOtherApps: true)
        let choice = VoidAlert.show(
            title: "Move stillpane to Applications?",
            message: """
                stillpane is running from \(location(of: bundleURL)). \
                Permissions, Launch at Login, and a clean uninstall all need the app \
                in one fixed place. stillpane can move itself to Applications and \
                reopen from there.
                """,
            buttons: ["Move to Applications", "Not Now"]
        )
        guard choice == 0 else { return false }

        let fileManager = FileManager.default
        // Stage the copy first: the copy is the long, failure-prone part
        // (disk space, permissions, a source that stops reading), and it must
        // not cost the user their working install when it fails. The staging
        // path shares the destination volume, so the final move is a rename.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent("stillpane-incoming-\(UUID().uuidString).app")
        do {
            do {
                try fileManager.copyItem(at: bundleURL, to: staging)
                // An older copy already there is exactly the conflicting-
                // install case; the fresher one the user just launched wins.
                // Its Trash location is kept so a failed rename can put it
                // back instead of leaving no install at all.
                var trashedOld: NSURL?
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.trashItem(at: destination, resultingItemURL: &trashedOld)
                }
                do {
                    try fileManager.moveItem(at: staging, to: destination)
                } catch {
                    if let trashedOld = trashedOld as URL? {
                        try? fileManager.moveItem(at: trashedOld, to: destination)
                    }
                    throw error
                }
            } catch {
                // A partial staging copy must not linger in /Applications.
                try? fileManager.removeItem(at: staging)
                throw error
            }
        } catch {
            VoidAlert.show(
                title: "Could not move stillpane",
                message: "\(error.localizedDescription)\n\nDrag the app to Applications yourself, then reopen it.",
                buttons: ["OK"]
            )
            return false
        }

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", destination.path]
        guard (try? open.run()) != nil else { return false }
        guard Subprocess.waitOrKill(open, timeout: 10),
            open.terminationStatus == 0
        else { return false }

        // Best-effort: works for a plain Downloads copy, fails harmlessly for
        // a translocated one (the mount is read-only and the original's real
        // path is not knowable from here).
        try? fileManager.trashItem(at: bundleURL, resultingItemURL: nil)
        NSApp.terminate(nil)
        return true
    }

    /// "the Downloads folder" reads better in the alert than a mount path.
    private static func location(of bundleURL: URL) -> String {
        if bundleURL.path.contains("/AppTranslocation/") {
            return "a temporary location macOS uses for apps opened in place"
        }
        return bundleURL.deletingLastPathComponent().path
    }
}
