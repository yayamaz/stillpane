import CoreGraphics

/// Pure geometry for the capture-moment overlays. The AppKit side supplies the
/// live screen numbers; the arithmetic lives here so it can be tested.
public enum ScreenGeometry {
    /// Converts a rect from CoreGraphics global display space (origin at the
    /// top-left of the primary display, y growing downwards - the space
    /// `kCGWindowBounds` reports in) to AppKit screen space (origin at the
    /// bottom-left of the primary display, y growing upwards).
    ///
    /// `primaryMaxY` is `NSScreen.screens[0].frame.maxY`: the primary screen is
    /// the origin of both spaces, so its top edge is the mirror line. Displays
    /// above or to the left of it have negative coordinates in both spaces and
    /// need no special case.
    public static func flipped(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryMaxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// The largest size with `size`'s aspect ratio that fits inside `box`.
    /// Never scales up: a window smaller than the box gets a smaller thumbnail
    /// rather than a blurry one.
    public static func aspectFit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / size.width, box.height / size.height, 1)
        return CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
    }
}
