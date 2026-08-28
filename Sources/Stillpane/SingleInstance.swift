import AppKit

/// One running stillpane per user. Two instances mean two hotkey monitors:
/// every chord fires two captures and two flashes, and the newest-capture
/// hook contract makes the results look random.
///
/// flock rather than an NSRunningApplication scan: the kernel releases the
/// lock the instant the holder exits, which is exactly the handoff a
/// `Relauncher` restart needs - the fresh copy starts while the old one is
/// still terminating and must wait for it, not kill itself.
@MainActor
enum SingleInstance {
    /// Held for the life of the process; never closed on purpose.
    private static var lockFileDescriptor: CInt = -1

    /// True when this process is, or just became, the only instance. Waits a
    /// few seconds for a terminating predecessor before conceding, so only a
    /// genuinely live duplicate is turned away.
    static func becomeOnlyInstance() -> Bool {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("stillpane-instance.lock")
        let descriptor = open(path, O_CREAT | O_RDWR, 0o600)
        // No lock beats no app: a broken temp dir must not block launching.
        guard descriptor >= 0 else { return true }
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                lockFileDescriptor = descriptor
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        close(descriptor)
        return false
    }

    /// The duplicate's parting act: put the copy that owns the lock on screen
    /// so the user's double-launch still feels like it did something.
    static func activateExisting() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate()
    }
}
