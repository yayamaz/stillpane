import AppKit
import StillpaneCore

/// Asks stillpane.dev once a day whether a newer release exists, and tells
/// the menu when one does. Notify-and-point only: the menu item opens the
/// release page and the app never downloads or replaces itself.
///
/// The request carries no identifiers - just a `stillpane/<version>` user
/// agent. Every failure is silent on purpose: before the endpoint exists the
/// check 404s, offline it times out, and both mean "nothing to announce".
@MainActor
final class UpdateChecker {
    static let automaticKey = "checkForUpdatesAutomatically"
    private static let feedURL = URL(string: "https://stillpane.dev/version.json")!
    private static let interval: TimeInterval = 24 * 60 * 60

    /// Default on; the menu toggle is the off switch.
    static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: automaticKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: automaticKey) }
    }

    private(set) var available: UpdateFeed.Info?
    var onUpdateAvailable: ((UpdateFeed.Info) -> Void)?
    private var timer: Timer?

    func start() {
        check()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.check() }
        }
        // The exact hour is irrelevant; letting the system coalesce the fire
        // keeps the check off battery-hostile wakeups.
        timer.tolerance = 60 * 60
        self.timer = timer
    }

    private func check() {
        guard Self.automatic, available == nil else { return }
        var request = URLRequest(url: Self.feedURL)
        request.setValue("stillpane/\(StillpaneVersion.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let data,
                (response as? HTTPURLResponse)?.statusCode == 200,
                let info = UpdateFeed.parse(data),
                UpdateFeed.isNewer(info.version, than: StillpaneVersion.version)
            else { return }
            Task { @MainActor in
                guard let self, self.available == nil else { return }
                self.available = info
                self.onUpdateAvailable?(info)
            }
        }.resume()
    }
}
