import AppKit
import SwiftUI

/// Hosts the setup assistant in a plain NSWindow. The app keeps its AppKit
/// lifecycle and its accessory activation policy; this is the one window it
/// ever shows.
@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?
    private static var state: OnboardingState?

    static func showIfNeeded() {
        // An unfinished walkthrough reopens no matter what the live checks
        // say: the permission steps restart the app mid-flow, and a user who
        // granted everything but never met the Claude Code step or took the
        // first capture is not set up.
        if OnboardingState.needsOnboardingByLocalChecks || OnboardingState.isInProgress {
            show()
            return
        }
        // Everything local looks fine; the only remaining reason to appear is a
        // missing plugin, and that check spawns a process. Keep it off the
        // launch path and open the window later if it comes back missing.
        ClaudeCLI.detectInBackground { detection in
            if !detection.pluginInstalled { show() }
        }
    }

    /// The menu's entry. A finished install opens on the status board; an
    /// unfinished one is still setup and opens where the work is.
    static func showStatus() {
        show(startOnStatus: true)
    }

    static func show(startOnStatus: Bool = false) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let newState = OnboardingState(startOnStatus: startOnStatus)
        let newWindow = NSWindow(
            // 700 tall fits the Welcome step at the shared type scale;
            // anything shorter clips the Get Started button.
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 730),
            // Resizable as a hedge: the step bodies are laid out for this size,
            // but a large accessibility text size can outgrow it, and a user
            // who cannot reach the Continue button is stuck.
            // .fullSizeContentView extends the content under the titlebar;
            // without it the transparent titlebar is an empty strip showing
            // whatever sits behind the window.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        // Named for the app switcher, unlabelled on screen: the void look
        // keeps the titlebar to its traffic lights.
        newWindow.title = "stillpane setup"
        newWindow.titleVisibility = .hidden
        newWindow.isReleasedWhenClosed = false
        newWindow.contentMinSize = NSSize(width: 660, height: 700)
        // The assistant commits to its own dark look - the focused void -
        // regardless of the system appearance, and pinning the appearance here
        // keeps every system-drawn control legible on it. The transparent
        // titlebar lets the void run all the way to the top edge.
        newWindow.appearance = NSAppearance(named: .darkAqua)
        newWindow.titlebarAppearsTransparent = true
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.isMovableByWindowBackground = true
        newWindow.contentView = NSHostingView(rootView: OnboardingView(state: newState))
        newWindow.center()
        newWindow.delegate = WindowCloser.shared

        state = newState
        window = newWindow
        newState.start()

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        teardown()
    }

    /// The first-capture rehearsal: the assistant steps aside so the whole
    /// screen can teach the chord. Hiding rather than closing keeps the state
    /// and its poll alive - the poll is what notices the capture and calls
    /// `endRehearsal` to bring the window back.
    static func beginRehearsal() {
        guard let window, let state else { return }
        RehearsalOverlay.show(
            onCancel: { endRehearsal() },
            onComplete: { state.completeRehearsal() }
        )
        // Overlay first, then hide: focus falls back to the user's app with
        // the dim already up, never through a frame of undimmed desktop.
        window.orderOut(nil)
    }

    static func endRehearsal() {
        RehearsalOverlay.dismiss()
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // The dismissal comes through a non-activating panel or a global key
        // monitor, neither of which counts as interacting with Stillpane, so
        // macOS may deny the activation - this shows the window regardless.
        window.orderFrontRegardless()
    }

    fileprivate static func teardown() {
        // Stops the poll timer, which is what keeps the state object alive.
        state?.stop()
        state = nil
        window = nil
        // A rehearsal must not outlive the window it would return to.
        RehearsalOverlay.dismiss()
    }
}

/// NSWindowDelegate has to be a class; this exists only to release the window
/// and its timer when the user closes it.
@MainActor
private final class WindowCloser: NSObject, NSWindowDelegate {
    static let shared = WindowCloser()

    func windowWillClose(_ notification: Notification) {
        OnboardingWindow.teardown()
    }
}
