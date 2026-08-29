import Foundation
import StillpaneCore

/// Installs the `claude` command line tool for a Mac that has none: the
/// one-press path for someone whose Claude Code lives in the Claude app.
///
/// The steps are the official install script's, performed natively: resolve
/// the current version, download the platform binary, verify it against the
/// manifest's SHA-256, then let the binary's own `install` command place
/// itself. Every write into Claude's install locations is made by Anthropic's
/// tool; stillpane only downloads and verifies, and never executes anything
/// whose digest it has not checked.
///
/// Everything here blocks on the network or a subprocess. Call it from a
/// background queue only.
enum ClaudeCLIInstaller {
    /// The official one-liner, offered for anyone who prefers to run the
    /// install themselves.
    static let terminalCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    /// `claude install` copies the binary into place and sets up its
    /// launcher; generous because a first run may still be warming caches.
    private static let installTimeout: TimeInterval = 300

    /// True when the git that Claude Code's plugin commands shell out to can
    /// run. `xcode-select -p` answers without side effects; probing `git`
    /// itself would trigger the OS's install dialog.
    static func developerToolsPresent() -> Bool {
        ClaudeCLI.run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"]).succeeded
    }

    /// Shows the OS's own Command Line Tools install dialog and returns; the
    /// install itself runs in Apple's UI and is noticed by polling
    /// `developerToolsPresent`.
    static func requestDeveloperTools() {
        _ = ClaudeCLI.run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["--install"])
    }

    enum Outcome: Sendable {
        case installed(URL)
        /// The user cancelled the download; not an error, nothing to report.
        case cancelled
        /// A one-line failure fit for the setup step.
        case failed(String)
    }

    /// Lets the UI cancel the download leg, the only stage long enough to
    /// deserve it. @unchecked Sendable: every access goes through the lock.
    final class InstallHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDownloadTask?
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            let task = task
            lock.unlock()
            task?.cancel()
        }

        fileprivate func attach(_ task: URLSessionDownloadTask) {
            lock.lock()
            let alreadyCancelled = cancelled
            self.task = task
            lock.unlock()
            if alreadyCancelled { task.cancel() }
        }

        fileprivate var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    /// `progress` reports the download leg only, as a 0...1 fraction of the
    /// manifest's published size, at most every whole percent; the other
    /// stages have no truthful signal and report nothing.
    static func install(
        handle: InstallHandle, progress: @escaping @Sendable (Double) -> Void
    ) -> Outcome {
        guard let rawVersion = fetchString(ClaudeCLIRelease.latestVersionURL),
            let version = ClaudeCLIRelease.version(fromLatest: rawVersion)
        else { return .failed("Could not reach claude.ai's download service.") }

        let platform = ClaudeCLIRelease.platform(isAppleSilicon: isAppleSilicon)
        guard let manifest = fetchData(ClaudeCLIRelease.manifestURL(version: version)),
            let checksum = ClaudeCLIRelease.checksum(fromManifest: manifest, platform: platform)
        else { return .failed("Could not read the checksum manifest for version \(version).") }

        let binary = FileManager.default.temporaryDirectory
            .appendingPathComponent("stillpane-claude-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: binary) }
        let downloaded = download(
            ClaudeCLIRelease.binaryURL(version: version, platform: platform), to: binary,
            handle: handle,
            expectedBytes: ClaudeCLIRelease.expectedBytes(fromManifest: manifest, platform: platform),
            progress: progress
        )
        if handle.isCancelled { return .cancelled }
        guard downloaded
        else { return .failed("The download of Claude Code \(version) failed.") }
        guard FileChecksum.sha256(of: binary) == checksum else {
            return .failed("The downloaded tool did not match its published checksum.")
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: binary.path
            )
        } catch {
            return .failed("Could not mark the downloaded tool executable.")
        }
        let install = ClaudeCLI.run(binary, ["install"], timeout: installTimeout)
        guard install.succeeded else {
            return .failed("Claude Code's installer did not finish: \(install.failureMessage)")
        }
        guard let claude = ClaudeCLI.locate() else {
            return .failed("The install finished, but the claude command was not found.")
        }
        return .installed(claude)
    }

    /// Rosetta-proof: asks the hardware rather than the process, so a
    /// translated build still fetches the arm64 binary. The sysctl does not
    /// exist on Intel, which reads as x64.
    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
        return value == 1
    }

    // MARK: - Blocking network helpers

    /// One value handed from a URLSession callback to the blocked caller.
    /// @unchecked Sendable: the semaphore orders the callback's write before
    /// the caller's read, and nothing else touches the box.
    private final class Handoff<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    private static func fetchData(_ url: URL) -> Data? {
        let handoff = Handoff<Data?>(nil)
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: url) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                handoff.value = data
            }
            done.signal()
        }.resume()
        done.wait()
        return handoff.value
    }

    private static func fetchString(_ url: URL) -> String? {
        fetchData(url).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Downloads straight to a file so the binary never has to fit in memory.
    /// Progress is received bytes over the manifest's size (never the
    /// response's own headers), reported on whole-percent steps so the
    /// observer is not flooded; no expected size means no reports.
    private static func download(
        _ url: URL, to destination: URL, handle: InstallHandle,
        expectedBytes: Int64?, progress: @escaping @Sendable (Double) -> Void
    ) -> Bool {
        let handoff = Handoff<Bool>(false)
        let done = DispatchSemaphore(value: 0)
        let task = session.downloadTask(with: url) { location, response, _ in
            if let location, let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try? FileManager.default.removeItem(at: destination)
                handoff.value =
                    (try? FileManager.default.moveItem(at: location, to: destination)) != nil
            }
            done.signal()
        }
        var observation: NSKeyValueObservation?
        if let expectedBytes {
            let reported = Handoff<Double>(0)
            observation = task.observe(\.countOfBytesReceived) { task, _ in
                let fraction = min(Double(task.countOfBytesReceived) / Double(expectedBytes), 1)
                guard fraction - reported.value >= 0.01 else { return }
                reported.value = fraction
                progress(fraction)
            }
        }
        handle.attach(task)
        task.resume()
        done.wait()
        observation?.invalidate()
        return handoff.value
    }
}
