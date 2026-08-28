import CoreGraphics

/// One row of the window server's front-to-back window list, reduced to the
/// fields capture-target selection needs.
public struct WindowListEntry: Equatable, Sendable {
    public let ownerPID: Int32
    public let layer: Int
    public let windowID: UInt32
    public let bounds: CGRect?
    public let alpha: Double
    /// The window server's name for the window. Populated only when the
    /// process holds Screen Recording permission; used as a tiebreak when
    /// matching the accessibility window, never for selection.
    public let title: String?

    public init(
        ownerPID: Int32, layer: Int, windowID: UInt32, bounds: CGRect?,
        alpha: Double, title: String? = nil
    ) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.windowID = windowID
        self.bounds = bounds
        self.alpha = alpha
        self.title = title
    }
}

/// Chooses which window a capture targets from the front-to-back window list.
///
/// The primary contract: the first normal-level (layer 0) window owned by
/// the active application, with no further filtering. The fallback exists
/// for activation theft - a screen recorder can hold `frontmostApplication`
/// while owning only an elevated, capture-excluded control strip, which
/// would put its five buttons in the capture instead of the window the user
/// is reading. When the active app owns no normal-level window at all, the
/// topmost normal-level window on screen - whoever owns it, minus stillpane
/// itself and invisible helper windows - is what the user is actually
/// looking at.
public enum WindowSelector {
    public struct Selection: Equatable, Sendable {
        public let entry: WindowListEntry
        public let isFallback: Bool
    }

    /// Fallback windows smaller than this are helper artifacts (event taps,
    /// offscreen buffers), never something a user meant to capture.
    public static let minimumFallbackSize: CGFloat = 50

    /// `entries` must be in front-to-back order, as
    /// `CGWindowListCopyWindowInfo` returns them.
    public static func select(
        entries: [WindowListEntry], activePID: Int32, ownPID: Int32
    ) -> Selection? {
        if let primary = entries.first(where: { $0.ownerPID == activePID && $0.layer == 0 }) {
            return Selection(entry: primary, isFallback: false)
        }
        let fallback = entries.first { entry in
            guard entry.layer == 0, entry.ownerPID != ownPID, entry.alpha > 0,
                let bounds = entry.bounds
            else { return false }
            return bounds.width >= minimumFallbackSize && bounds.height >= minimumFallbackSize
        }
        return fallback.map { Selection(entry: $0, isFallback: true) }
    }

    /// AX and CG frames of the same window differ by a point or two on some
    /// apps; anything past that is a different window.
    public static let matchTolerance: CGFloat = 2

    /// The one definition of "same window, seen from AX and CG" - both the
    /// primary cross-check and the activation-theft fallback compare with it,
    /// so the two paths cannot drift.
    public static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= matchTolerance
            && abs(a.minY - b.minY) <= matchTolerance
            && abs(a.width - b.width) <= matchTolerance
            && abs(a.height - b.height) <= matchTolerance
    }

    /// The active app's window-list entry for the focused accessibility
    /// window, matched by geometry the way the activation-theft fallback
    /// matches in the other direction. Same-geometry twins tiebreak on the
    /// window server's title when it is available, else the topmost wins.
    /// Nil means no entry of the active app matches the focused window - the
    /// caller must not screenshot a window the text did not come from.
    public static func matchEntry(
        axFrame: CGRect, axTitle: String?, entries: [WindowListEntry], activePID: Int32
    ) -> WindowListEntry? {
        let matches = entries.filter { entry in
            guard entry.ownerPID == activePID, entry.layer == 0,
                let bounds = entry.bounds
            else { return false }
            return framesMatch(bounds, axFrame)
        }
        guard let first = matches.first else { return nil }
        return matches.first { entry in
            guard let title = entry.title, !title.isEmpty else { return false }
            return title == axTitle
        } ?? first
    }
}
