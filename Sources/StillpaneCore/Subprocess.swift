import Foundation

/// Bounded waiting for child processes.
///
/// `Process.waitUntilExit()` alone is an unbounded trust in the child: a
/// wedged subprocess would pin its caller forever, and a capture pipeline
/// serialized behind one would be silently dead until relaunch. Every
/// subprocess wait in the app goes through here instead.
public enum Subprocess {
    /// How long a terminated child gets to exit before the escalation stops
    /// asking. SIGKILL cannot be caught, so the reap after it is prompt.
    private static let gracePeriod: TimeInterval = 2

    /// Waits for a running process up to `timeout`. Returns true when the
    /// child exited on its own. On timeout it escalates - SIGTERM, a short
    /// grace, then SIGKILL - and returns false. The child is reaped either
    /// way: `terminationStatus` is valid as soon as this returns.
    public static func waitOrKill(_ process: Process, timeout: TimeInterval) -> Bool {
        if wait(for: process, until: Date().addingTimeInterval(timeout)) { return true }
        process.terminate()
        if !wait(for: process, until: Date().addingTimeInterval(gracePeriod)) {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        return false
    }

    private static func wait(for process: Process, until deadline: Date) -> Bool {
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return !process.isRunning
    }
}
