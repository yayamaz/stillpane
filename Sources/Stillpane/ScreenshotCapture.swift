import CoreGraphics
import Foundation
import ImageIO
import StillpaneCore
import UniformTypeIdentifiers

enum ScreenshotCapture {
    /// Captures one window (no shadow), downscaled to the width beyond which
    /// Claude's vision gains nothing. Nil on any failure; callers degrade to a
    /// text-only capture.
    ///
    /// `-x` (do not play sounds) is deliberately present: stillpane plays its
    /// own capture sound for both capture modes, on the frame that carries the
    /// flash, so the system shutter here would double it - and would land with
    /// the subprocess rather than with the moment the user sees.
    static func pngData(windowID: CGWindowID) -> Data? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stillpane-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-o", "-x", "-l", String(windowID), tempURL.path]
        do {
            try process.run()
        } catch {
            return nil
        }
        // Bounded, because this wait sits inside the capture pipeline's
        // serialization: an unkilled hang here would silently swallow every
        // later chord until the app restarts. A window capture is normally
        // sub-second, so ten seconds is already a broken subprocess.
        guard Subprocess.waitOrKill(process, timeout: 10) else { return nil }
        guard process.terminationStatus == 0,
            let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let resized = ImageResizer.downscaled(image, maxWidth: ImageResizer.claudeMaxWidth)
        return encodePNG(resized)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
