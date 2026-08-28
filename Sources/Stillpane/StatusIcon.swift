import AppKit

/// The menu bar icon: the brand's option glyph, drawn from the same 34x26
/// geometry as the wordmark and the app icon. A template image, so macOS
/// recolors it for menu bar appearance, highlight, and the paused
/// `appearsDisabled` dim.
enum StatusIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let s = min(rect.width / 34, rect.height / 26)
            let ox = rect.midX - 34 * s / 2
            let oy = rect.midY - 26 * s / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                // The glyph coordinates are y-down; AppKit draws y-up.
                NSPoint(x: ox + x * s, y: oy + (26 - y) * s)
            }
            let path = NSBezierPath()
            path.move(to: p(2, 4))
            path.line(to: p(11.5, 4))
            path.line(to: p(24.5, 22))
            path.line(to: p(32, 22))
            path.move(to: p(23.5, 4))
            path.line(to: p(32, 4))
            path.lineWidth = 2.6 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
