import AppKit

/// A small self-dismissing confirmation panel. No notification permission
/// needed; appears top-center of the active screen and fades out.
@MainActor
enum HUD {
    private static var panel: NSPanel?

    static func flash(_ message: String) {
        panel?.close()

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let padding: CGFloat = 18
        let size = NSSize(width: label.frame.width + padding * 2, height: 40)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.maxY - size.height - 24
        )

        let newPanel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        newPanel.level = .statusBar
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.ignoresMouseEvents = true
        // NSWindow defaults to releasing itself on close, which over-releases
        // under ARC while `panel` still holds a reference.
        newPanel.isReleasedWhenClosed = false
        // .hudWindow follows the system appearance; pin it dark so the white
        // label stays legible in Light Mode.
        newPanel.appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = size.height / 2
        background.layer?.masksToBounds = true
        // Hairline so the pill keeps an edge over dark wallpapers.
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        label.frame.origin = NSPoint(x: padding, y: (size.height - label.frame.height) / 2)
        background.addSubview(label)
        newPanel.contentView = background
        newPanel.orderFrontRegardless()
        panel = newPanel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak newPanel] in
            guard let newPanel else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.3
                    newPanel.animator().alphaValue = 0
                },
                completionHandler: {
                    // Animation completion handlers run on the main thread.
                    MainActor.assumeIsolated { newPanel.close() }
                })
        }
    }
}
