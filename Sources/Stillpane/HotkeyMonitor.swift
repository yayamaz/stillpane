import AppKit
import StillpaneCore

/// Feeds global modifier-flag events into ChordDetector, binding the chord to
/// both Option keys held together. Double-Command is left alone because the
/// Codex app already binds it to its own Appshots.
/// NSEvent global monitors are event-driven: zero CPU while idle.
@MainActor
final class HotkeyMonitor {
    // Device-dependent flag bits for left and right Option keys
    // (NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK).
    private static let leftOptionMask: UInt = 0x20
    private static let rightOptionMask: UInt = 0x40

    /// One flagsChanged event read as chord state. The setup rehearsal decodes
    /// events through this too, so the demo mirrors the user's fingers with
    /// exactly the reading a real capture uses.
    ///
    /// Only Control/Command disqualify the chord, so ⌘⌥ shortcuts in other
    /// apps stay safe. Shift rides along instead of cancelling: it selects the
    /// other capture mode (`CaptureMode.resolve`). That is safe for the same
    /// reason the chord itself is - both Option keys are required, and nobody
    /// holds both to type a ⌥⇧ character. Caps Lock and the Fn flag are
    /// latching states, not part of a deliberate shortcut.
    static func chordState(of event: NSEvent)
        -> (left: Bool, right: Bool, others: Bool, shift: Bool)
    {
        let raw = event.modifierFlags.rawValue
        return (
            left: raw & leftOptionMask != 0,
            right: raw & rightOptionMask != 0,
            others: !event.modifierFlags.intersection([.control, .command]).isEmpty,
            shift: event.modifierFlags.contains(.shift)
        )
    }

    private var detector = ChordDetector()
    private var monitors: [Any] = []

    /// Global AND local monitors: a global monitor never receives events
    /// delivered to this app, so without the local one the chord goes silent
    /// whenever stillpane itself is active - the setup window after a
    /// rehearsal, or right after opening the menu. An event reaches exactly
    /// one of the two, so the shared detector sees each press once.
    /// `shiftHeld` is read from the very event that completes the chord, so
    /// Shift has to already be down when the second Option lands - the chord
    /// fires on modifier-down and nothing waits to sample it.
    func start(onChord: @escaping @MainActor (_ shiftHeld: Bool) -> Void) {
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let chord = Self.chordState(of: event)
            if self.detector.handle(
                leftKeyDown: chord.left, rightKeyDown: chord.right,
                otherModifiersDown: chord.others
            ) {
                onChord(chord.shift)
            }
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handle($0) },
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
                handle($0)
                return $0
            },
        ].compactMap { $0 }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }
}
