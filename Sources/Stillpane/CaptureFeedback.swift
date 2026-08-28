import AppKit
import StillpaneCore

/// The capture moment: a white flash over the captured window holds for a
/// beat, shrinks quickly toward the top-center of its screen - filed up toward
/// the menu bar, where the app lives - then the landed card becomes a
/// thumbnail of the shot, holds, and fades away. The shutter sound comes from
/// `screencapture` itself.
///
/// The panel is borderless, non-activating and mouse-transparent, so the app
/// the user is working in never loses focus and nothing lands under the
/// pointer. `isReleasedWhenClosed` is off: NSWindow's default of releasing
/// itself on close over-releases under ARC while a static still holds the
/// reference.
@MainActor
enum CaptureFeedback {
    private static let flashAlpha: CGFloat = 0.85
    private static let holdDuration: TimeInterval = 0.1
    private static let shrinkDuration: TimeInterval = 0.4
    private static let arrivalTopMargin: CGFloat = 8
    private static let thumbnailBox = CGSize(width: 260, height: 180)
    private static let revealDuration: TimeInterval = 0.22
    private static let thumbnailHold: TimeInterval = 0.6
    private static let fadeDuration: TimeInterval = 0.3
    /// The white card never waits forever for a shot that is not coming:
    /// the pipeline's completion normally resolves it, this is the backstop.
    private static let waitLimit: TimeInterval = 8

    private static var flashPanel: NSPanel?
    private static var pendingImage: NSImage?
    private static var hasArrived = false
    private static var scheduled: [DispatchWorkItem] = []

    /// stillpane's capture sound, played for every capture and by the
    /// rehearsal, so the demo cannot drift from the real moment and both
    /// capture modes feel like the same gesture.
    ///
    /// `screencapture` is run with `-x` so the system shutter never doubles
    /// this. Loaded once: a first-play disk read on the main thread would
    /// land right on the capture instant. The system fallback covers a
    /// binary run outside the app bundle, where there are no resources.
    private static let captureSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "capture", withExtension: "aiff"),
            let sound = NSSound(contentsOf: url, byReference: false)
        else { return NSSound(named: "Pop") }
        return sound
    }()

    /// Every capture sounds, including one that lands while the last is still
    /// ringing. `play()` on an NSSound that is already playing does nothing
    /// at all, which would leave the second of two quick captures silent;
    /// stopping first rewinds it and guarantees the retrigger.
    static func playCaptureSound() {
        captureSound?.stop()
        captureSound?.play()
    }

    /// `windowFrame` is in CoreGraphics global display coordinates, as
    /// `kCGWindowBounds` reports it.
    ///
    /// This cannot leak into the screenshot: `screencapture -l <windowid>`
    /// composites one window by ID, so an overlay in front of it is not part of
    /// the image.
    static func flash(windowFrame: CGRect) {
        // A second capture replaces the first moment outright.
        reset()
        let frame = appKitFrame(windowFrame)
        guard frame.width >= 1, frame.height >= 1 else { return }
        guard let visible = screen(for: windowFrame)?.visibleFrame else { return }

        let panel = overlayPanel(frame: frame, level: .screenSaver)
        let fill = NSView(frame: NSRect(origin: .zero, size: frame.size))
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.white.cgColor
        // Invisible at window size, reads once the panel has shrunk small.
        fill.layer?.cornerRadius = 12
        fill.layer?.cornerCurve = .continuous
        fill.layer?.masksToBounds = true
        fill.autoresizingMask = [.width, .height]
        panel.contentView = fill
        panel.alphaValue = flashAlpha
        panel.orderFrontRegardless()
        flashPanel = panel

        // Deferred one runloop turn: audio spin-up must never hold back the
        // frame that carries the flash.
        DispatchQueue.main.async { playCaptureSound() }

        // The flight lands directly at the thumbnail's size, just under the
        // menu bar at the screen's horizontal center: the shot has the
        // window's aspect, so the shrunken window IS the thumbnail and the
        // image only has to surface in it - no second size change.
        let size = StillpaneCore.ScreenGeometry.aspectFit(frame.size, in: thumbnailBox)
        let target = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - arrivalTopMargin,
            width: size.width,
            height: size.height
        )

        after(holdDuration) {
            guard flashPanel === panel else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = shrinkDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().setFrame(target, display: false)
                },
                completionHandler: {
                    // Animation completion handlers run on the main thread.
                    MainActor.assumeIsolated {
                        guard flashPanel === panel else { return }
                        hasArrived = true
                        if let image = pendingImage {
                            reveal(image, in: panel)
                        } else {
                            after(waitLimit) {
                                guard flashPanel === panel, pendingImage == nil else { return }
                                fadeOut(panel)
                            }
                        }
                    }
                })
        }
    }

    /// The shot, once the pipeline delivers it. If the card is still in
    /// flight the image waits for the landing; a capture with no flash (no
    /// frame to fly from) has no card to fill and shows nothing.
    static func showThumbnail(_ image: NSImage) {
        guard let panel = flashPanel else { return }
        pendingImage = image
        if hasArrived { reveal(image, in: panel) }
    }

    /// The text-only capture's payoff: the landed card fills with the shape
    /// of the text it took, so the moment resolves into something instead of
    /// a white rectangle fading out. Returns false when there is no card to
    /// fill, which is the caller's cue to say it in words instead.
    @discardableResult
    static func showTextCard() -> Bool {
        guard let panel = flashPanel else { return false }
        let image = textCardImage(size: panel.frame.size)
        pendingImage = image
        if hasArrived { reveal(image, in: panel) }
        return true
    }

    /// Drawn rather than photographed: rows of soft bars on the void, reading
    /// as a page of text at thumbnail size without pretending to be a shot.
    private static func textCardImage(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            NSColor(white: 0.1, alpha: 1).setFill()
            rect.fill()
            let inset = max(10, rect.width * 0.09)
            let lineHeight = max(3, rect.height * 0.045)
            let gap = lineHeight * 1.5
            // A ragged right edge is what makes a block of bars read as prose.
            let widths: [CGFloat] = [1.0, 0.82, 0.93, 0.66, 0.88, 0.74, 0.96, 0.58]
            var y = inset
            for (index, fraction) in widths.enumerated() {
                guard y + lineHeight <= rect.height - inset else { break }
                NSColor(white: 1, alpha: index == 0 ? 0.34 : 0.17).setFill()
                let width = (rect.width - inset * 2) * fraction
                NSBezierPath(
                    roundedRect: NSRect(x: inset, y: y, width: width, height: lineHeight),
                    xRadius: lineHeight / 2, yRadius: lineHeight / 2
                ).fill()
                y += lineHeight + gap
            }
            return true
        }
    }

    /// For captures that end with nothing to show after the flash - a failed
    /// pipeline - so the white card does not linger.
    static func dismiss() {
        guard let panel = flashPanel else { return }
        fadeOut(panel)
    }

    /// The shot surfaces inside the landed card - same place, same size -
    /// holds, then fades away.
    private static func reveal(_ image: NSImage, in panel: NSPanel) {
        pendingImage = nil
        guard let fill = panel.contentView else {
            fadeOut(panel)
            return
        }

        // A hairline so the card keeps an edge over a bright window once the
        // white fill is covered by the shot.
        fill.layer?.borderWidth = 1
        fill.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        let imageView = NSImageView(frame: fill.bounds)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.alphaValue = 0
        fill.addSubview(imageView)
        panel.hasShadow = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            imageView.animator().alphaValue = 1
        }
        after(revealDuration + thumbnailHold) {
            guard flashPanel === panel else { return }
            fadeOut(panel)
        }
    }

    private static func fadeOut(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                MainActor.assumeIsolated {
                    panel.close()
                    if flashPanel === panel { reset() }
                }
            })
    }

    private static func reset() {
        for item in scheduled { item.cancel() }
        scheduled = []
        flashPanel?.close()
        flashPanel = nil
        pendingImage = nil
        hasArrived = false
    }

    private static func after(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated(body) }
        scheduled.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Shared

    private static func overlayPanel(frame: NSRect, level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        // Follow the user across Spaces and full-screen apps instead of pinning
        // the overlay to whichever Space it was born on.
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]
        return panel
    }

    /// CoreGraphics reports window bounds relative to the top-left of the
    /// primary display; AppKit windows are placed relative to its bottom-left.
    private static func appKitFrame(_ cgFrame: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return cgFrame }
        return StillpaneCore.ScreenGeometry.flipped(cgFrame, primaryMaxY: primary.frame.maxY)
    }

    /// The display the captured window sits on: the one containing its center,
    /// else the one it overlaps most, else wherever the pointer is.
    private static func screen(for cgFrame: CGRect?) -> NSScreen? {
        guard let cgFrame else { return NSScreen.main }
        let frame = appKitFrame(cgFrame)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return containing
        }
        let overlapping = NSScreen.screens.max { lhs, rhs in
            area(lhs.frame.intersection(frame)) < area(rhs.frame.intersection(frame))
        }
        if let overlapping, area(overlapping.frame.intersection(frame)) > 0 { return overlapping }
        return NSScreen.main
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
