import AppKit
import ApplicationServices
import StillpaneCore

@MainActor
enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Also what registers Stillpane in the Accessibility list, so it runs even
    /// though its dialog is only a doorway to System Settings: a fresh install
    /// that never called this can be missing from the pane entirely.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    /// `CGPreflightScreenCaptureAccess` answers from a per-process cache, so a
    /// grant landing mid-run never flips it for this process. A freshly
    /// spawned copy of this binary (`--preflight-screen`, handled in
    /// main.swift before the app starts) reads the live state instead; its
    /// exit code is the answer. The completion is delivered on the main
    /// thread.
    static func probeScreenRecording(completion: @escaping @Sendable (Bool) -> Void) {
        guard let executable = Bundle.main.executableURL else {
            // Bare-binary runs (swift run) have no bundle to probe; the
            // in-process answer is the best available.
            completion(screenRecordingGranted)
            return
        }
        let probe = Process()
        probe.executableURL = executable
        probe.arguments = ["--preflight-screen"]
        probe.terminationHandler = { process in
            let granted = process.terminationStatus == 0
            DispatchQueue.main.async { completion(granted) }
        }
        do {
            try probe.run()
        } catch {
            DispatchQueue.main.async { completion(false) }
        }
    }

    static let accessibilityService = "Accessibility"
    static let screenRecordingService = "ScreenCapture"

    /// Removes stillpane's TCC rows for one service. A row created by a build
    /// signed under a different identity shows as enabled in System Settings
    /// while the live check stays false, and the pane's own toggle only
    /// re-approves the dead identity - removing the row and granting fresh is
    /// the only recovery. tccutil returns in well under a second, so the
    /// synchronous wait is imperceptible next to the relaunch that follows.
    static func resetPermissionRecord(service: String) {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = [
            "reset", service, Bundle.main.bundleIdentifier ?? "app.stillpane.Stillpane",
        ]
        do {
            try reset.run()
        } catch {
            return
        }
        _ = Subprocess.waitOrKill(reset, timeout: 10)
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
