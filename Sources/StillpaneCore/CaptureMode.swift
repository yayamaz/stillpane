/// Which halves of a capture the chord is asking for.
///
/// The menu's "Swap Capture Modes" decides which one the plain chord takes;
/// holding Shift asks for the other. Inverting rather than always meaning
/// text-only keeps the gesture useful whichever way the default is set, and
/// lets the menu state both outcomes as plain fact rather than as a rule the
/// reader has to apply.
public enum CaptureMode: Sendable, Equatable {
    case screenshotAndText
    case textOnly

    public static func resolve(defaultTextOnly: Bool, shiftHeld: Bool) -> CaptureMode {
        defaultTextOnly != shiftHeld ? .textOnly : .screenshotAndText
    }

    public var wantsScreenshot: Bool { self == .screenshotAndText }
}
