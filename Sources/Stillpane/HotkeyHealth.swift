import Foundation

/// Whether this process's hotkey monitor is dead.
///
/// An NSEvent global monitor installed while the process was untrusted never
/// receives anything, no matter when the grant lands, so the only fix is a
/// relaunch. `AppDelegate` records the fact at launch and clears it by
/// relaunching; the setup status board and every problem report have to say
/// so too, which is why the fact lives here rather than inside the delegate.
@MainActor
enum HotkeyHealth {
    static var needsRestart = false

    /// Never reports a bare "granted" while a monitor installed before the
    /// grant is still the live one: the permission is fine and the hotkey is
    /// not, and only saying so keeps the user from concluding the app is
    /// broken.
    static var accessibilityStatus: String {
        guard Permissions.accessibilityGranted else { return "missing" }
        return needsRestart ? "granted - restart stillpane to activate the hotkey" : "granted"
    }
}
