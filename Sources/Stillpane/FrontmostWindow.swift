import AppKit
import ApplicationServices
import StillpaneCore

// @unchecked Sendable: AXUIElement is a thread-safe CF type but is not
// marked Sendable; the capture pipeline hands this value to a worker queue.
struct FrontmostTarget: @unchecked Sendable {
    let appName: String
    let bundleID: String
    let pid: pid_t
    let windowTitle: String
    let windowID: CGWindowID?
    /// The window's bounds in CoreGraphics global display coordinates (origin
    /// at the top-left of the primary display). The capture-moment overlays
    /// need this before the screenshot is taken; nil when the window server
    /// reports no readable bounds.
    let frame: CGRect?
    let axWindow: AXUIElement
}

enum FrontmostWindow {
    static func current() -> FrontmostTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        // A timeout set on one AX object bounds only that object (the header
        // is explicit that it does not extend to related objects), so the
        // bound goes on the system-wide object: every AX call this process
        // makes - these reads and the whole tree walk - runs under it.
        AXUIElementSetMessagingTimeout(
            AXUIElementCreateSystemWide(), AXTreeReader.messagingTimeout)

        let entries = windowListEntries()
        let selection = WindowSelector.select(
            entries: entries,
            activePID: pid,
            ownPID: ProcessInfo.processInfo.processIdentifier
        )

        // Activation theft: the active app owns no normal-level window (a
        // recorder's elevated control strip, say), so the topmost normal
        // window on screen is what the user is looking at. A failed AX match
        // falls through to the original path - a mismatched tree would be
        // worse than a degraded capture.
        if let selection, selection.isFallback,
            let target = fallbackTarget(for: selection.entry)
        {
            return target
        }

        let axApp = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let axWindow = unsafeDowncast(windowRef, to: AXUIElement.self)

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""

        // The screenshot must show the window the text came from. The CG pick
        // (first layer-0 window of the active app) and the AX focus are read
        // from different subsystems, and a multi-window app or a focus race
        // can make them disagree; match them by geometry the way the fallback
        // path already does, and degrade to a text-only capture rather than
        // pair a screenshot with the wrong tree. An unreadable AX frame keeps
        // the CG pick: a divergence that cannot be detected is not worth
        // degrading every capture over.
        var primary = selection?.isFallback == false ? selection?.entry : nil
        if primary != nil, let focusedFrame = axFrame(of: axWindow) {
            primary = WindowSelector.matchEntry(
                axFrame: focusedFrame, axTitle: title, entries: entries, activePID: pid)
        }
        return FrontmostTarget(
            appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "",
            pid: pid,
            windowTitle: title,
            windowID: primary?.windowID,
            frame: primary?.bounds,
            axWindow: axWindow
        )
    }

    /// The window server's front-to-back list, reduced to selection fields.
    /// One pass serves both the primary lookup and the fallback, so the id
    /// and the frame always describe the same window.
    private static func windowListEntries() -> [WindowListEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int,
                let number = info[kCGWindowNumber as String] as? CGWindowID
            else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            return WindowListEntry(
                ownerPID: ownerPID,
                layer: layer,
                windowID: number,
                bounds: bounds,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                title: info[kCGWindowName as String] as? String
            )
        }
    }

    /// Builds a target from a fallback selection - the topmost normal window
    /// of an app that is not active. The AX window has to be matched to the
    /// CG window by geometry (macOS offers no public bridge between the two);
    /// nil on anything short of a confident match, because a screenshot of
    /// one window with the text tree of another is worse than a degraded
    /// capture of the active app.
    private static func fallbackTarget(for entry: WindowListEntry) -> FrontmostTarget? {
        guard let bounds = entry.bounds,
            let app = NSRunningApplication(processIdentifier: entry.ownerPID)
        else { return nil }
        let axApp = AXUIElementCreateApplication(entry.ownerPID)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else { return nil }

        let matches = windows.filter { window in
            guard let frame = axFrame(of: window) else { return false }
            return WindowSelector.framesMatch(frame, bounds)
        }
        guard let first = matches.first else { return nil }
        // Same-geometry twins: the window server's name for the window is
        // the only cross-check available (it needs Screen Recording, so it
        // can be nil); with nothing to compare, the first match stands.
        let axWindow =
            matches.first { window in
                guard let cgName = entry.title, !cgName.isEmpty else { return false }
                return axTitle(of: window) == cgName
            } ?? first

        return FrontmostTarget(
            appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleID: app.bundleIdentifier ?? "",
            pid: entry.ownerPID,
            windowTitle: axTitle(of: axWindow) ?? entry.title ?? "",
            windowID: entry.windowID,
            frame: bounds,
            axWindow: axWindow
        )
    }

    /// AX reports position and size in the same top-left global coordinates
    /// the window server uses, so the two frames compare directly.
    private static func axFrame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard let positionRef, CFGetTypeID(positionRef) == AXValueGetTypeID(),
            let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(
                unsafeDowncast(positionRef, to: AXValue.self), .cgPoint, &position),
            AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func axTitle(of window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        return titleRef as? String
    }
}
