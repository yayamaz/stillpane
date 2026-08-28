/// Detects a chord where the left and right halves of one modifier pair are
/// held together with no other modifiers, from a stream of modifier-flag
/// states. The app binds it to the Option keys. Fires exactly once per chord;
/// re-arms only after all modifiers are released.
public struct ChordDetector: Sendable {
    private var armed = true

    public init() {}

    public mutating func handle(
        leftKeyDown: Bool,
        rightKeyDown: Bool,
        otherModifiersDown: Bool
    ) -> Bool {
        if otherModifiersDown {
            armed = false
            return false
        }
        if leftKeyDown && rightKeyDown {
            guard armed else { return false }
            armed = false
            return true
        }
        if !leftKeyDown && !rightKeyDown {
            armed = true
        }
        return false
    }
}
