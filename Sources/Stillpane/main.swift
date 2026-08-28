import AppKit
import StillpaneCore

// Debug builds only: print the frontmost window's markdown after a 3s delay
// (time to focus the window you want captured). Used for manual testing.
// Excluded from release builds so the shipped binary offers no argument-driven
// capture path a local process could invoke under stillpane's TCC grants.
#if DEBUG
    if CommandLine.arguments.contains("--capture-text") {
        guard AXIsProcessTrusted() else {
            FileHandle.standardError.write(Data("Grant Accessibility permission first.\n".utf8))
            exit(1)
        }
        Thread.sleep(forTimeInterval: 3)
        guard let target = FrontmostWindow.current() else {
            FileHandle.standardError.write(Data("No frontmost window found.\n".utf8))
            exit(1)
        }
        let read = AXTreeReader.read(target: target)
        print(MarkdownRenderer.render(read.root, truncated: read.truncated))
        exit(0)
    }

    if CommandLine.arguments.contains("--capture-shot") {
        Thread.sleep(forTimeInterval: 3)
        guard let target = FrontmostWindow.current(), let windowID = target.windowID else {
            FileHandle.standardError.write(Data("No frontmost window found.\n".utf8))
            exit(1)
        }
        guard let png = ScreenshotCapture.pngData(windowID: windowID) else {
            FileHandle.standardError.write(Data("Screenshot failed. Check Screen Recording permission.\n".utf8))
            exit(1)
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("stillpane-debug.png")
        try? png.write(to: out)
        print(out.path)
        exit(0)
    }
#endif

// Out-of-process Screen Recording probe: `CGPreflightScreenCaptureAccess` is
// answered from a per-process cache, so the running app cannot see a grant
// that lands mid-run. It spawns a short-lived copy of itself with this flag -
// the fresh process reads the live TCC state - and the exit code carries the
// whole answer. Ships in release builds deliberately: it reads one bit about
// stillpane's own permission and exits, with no capture path and no output.
if CommandLine.arguments.contains("--preflight-screen") {
    exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
