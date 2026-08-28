import AppKit
import StillpaneCore

/// Runs one full capture: frontmost window -> AX markdown + screenshot
/// -> CaptureStore. Heavy work happens off the main thread.
@MainActor
final class CaptureCoordinator {
    private let store = CaptureStore(rootURL: CaptureStore.defaultRootURL)
    private nonisolated static let expiry: TimeInterval = 24 * 3600

    /// One capture at a time. Repeated chords would otherwise stack independent
    /// tree walks and `screencapture` subprocesses against the same window, and
    /// a slow target is exactly when a user presses the chord again.
    private var isCapturing = false

    /// True while a capture is anywhere in the pipeline. Uninstall waits on
    /// this: teardown must not delete the capture root under a worker that is
    /// about to recreate it.
    var isBusy: Bool { isCapturing }

    /// Prunes captures older than 24 hours, off the main thread. Called at
    /// launch and hourly - a completed capture prunes inline in `capture` -
    /// so a final sensitive capture expires while the app idles instead of
    /// waiting for another capture.
    func expireOldCaptures() {
        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            store.expire(olderThan: Self.expiry)
        }
    }

    /// The capture root, created if absent and repaired to owner-only, for
    /// direct browsing. nil when the root exists but is not a plain directory.
    func preparedRootURL() -> URL? {
        do {
            try store.prepareRoot()
            return store.rootURL
        } catch {
            return nil
        }
    }

    /// `willCapture` runs synchronously, on the chord, once the target is known
    /// and before any work starts: the capture moment has to land on the key
    /// press rather than after a slow tree walk.
    /// `includeScreenshot` false is a text-only capture: `screencapture` is
    /// never spawned, so there is no picture, no shutter, and no window server
    /// round trip - not a shot taken and discarded.
    func capture(
        includeScreenshot: Bool = true,
        willCapture: (FrontmostTarget) -> Void = { _ in },
        completion: @escaping @MainActor (Result<CaptureInput, CaptureError>) -> Void
    ) {
        guard !isCapturing else { return }
        guard let target = FrontmostWindow.current() else {
            completion(.failure(.noWindow))
            return
        }
        isCapturing = true
        willCapture(target)
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async {
            // The screenshot goes first: it is the half with a visible moment
            // (the system shutter sound), so it belongs next to the flash, and
            // the image then matches the screen as it was at the chord rather
            // than after the tree walk.
            let png =
                includeScreenshot
                ? target.windowID.flatMap { ScreenshotCapture.pngData(windowID: $0) } : nil
            let read = AXTreeReader.read(target: target)
            let markdown = MarkdownRenderer.render(read.root, truncated: read.truncated)
            let input = CaptureInput(
                app: target.appName,
                windowTitle: target.windowTitle,
                url: firstURL(in: read.root),
                markdown: markdown,
                pngData: png,
                capturedAt: Date()
            )
            let result: Result<CaptureInput, CaptureError>
            do {
                try store.save(input)
                store.expire(olderThan: Self.expiry)
                result = .success(input)
            } catch {
                // The HUD only has room for a generic message; keep the real
                // reason where `log show` and a terminal launch can find it.
                FileHandle.standardError.write(
                    Data("stillpane: could not save capture: \(error.localizedDescription)\n".utf8)
                )
                result = .failure(.writeFailed(error))
            }
            // The single exit for every outcome above, so the flag cannot be
            // left set by a success, a failure, or a throw.
            Task { @MainActor in
                self.isCapturing = false
                completion(result)
            }
        }
    }
}

/// The document URL when the window is a browser: first AXWebArea URL.
private func firstURL(in node: AXNode) -> String? {
    if node.role == "AXWebArea", let url = node.url { return url }
    for child in node.children {
        if let url = firstURL(in: child) { return url }
    }
    return nil
}

enum CaptureError: Error {
    case noWindow
    case writeFailed(Error)

    var message: String {
        switch self {
        case .noWindow: return "No frontmost window"
        case .writeFailed: return "Could not save capture"
        }
    }
}
