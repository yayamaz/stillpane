import AppKit
import StillpaneCore

/// Restarts Stillpane in place.
///
/// An NSEvent global monitor installed before the Accessibility grant stays
/// dead for the life of the process: TCC decides at monitor-install time. Only
/// a process started after the grant can listen for the hotkey, so the app
/// relaunches itself rather than quietly failing to capture. Two callers need
/// this (the setup assistant's Accessibility step and AppDelegate's self-heal),
/// so it lives here rather than being duplicated.
///
/// Terminating is conditional on `open` reporting that it accepted the launch.
/// Quitting on anything less would risk leaving the user with no running app
/// and no message explaining why.
@MainActor
enum Relauncher {
    /// Why a relaunch did not happen. Success does not return: the process
    /// terminates before `relaunch` can hand a value back.
    enum Failure {
        /// Running the bare binary from a build directory: nothing to reopen.
        case notABundle
        case openFailed
    }

    static let manualRelaunchMessage =
        "Accessibility is granted. Quit stillpane from the menu bar and open it again to start capturing."

    /// A successful spawn is followed by `NSApp.terminate`, which does not come
    /// back on the normal path. If it ever did (a delegate cancelling
    /// termination, a second caller racing in on the same run loop turn), this
    /// keeps a second call from spawning a third instance.
    private static var didSpawn = false

    /// Launches a fresh copy and terminates this one. Returns only on failure.
    @discardableResult
    static func relaunch(beforeTerminating: () -> Void = {}) -> Failure? {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return .notABundle }

        if !didSpawn {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-n", bundlePath]
            do {
                try open.run()
            } catch {
                return .openFailed
            }
            guard Subprocess.waitOrKill(open, timeout: 10),
                open.terminationStatus == 0
            else { return .openFailed }
            didSpawn = true
        }

        beforeTerminating()
        NSApp.terminate(nil)
        return nil
    }
}
