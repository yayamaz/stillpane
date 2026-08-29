import AppKit
import StillpaneCore

/// Asks stillpane.dev once a day whether a newer release exists, and tells
/// the menu when one does. Notify-and-point only: the menu item opens the
/// release page and the app never downloads or replaces itself.
///
/// The request carries no identifiers - just a `stillpane/<version>` user
/// agent. Every failure is silent on purpose: before the endpoint exists the
/// check 404s, offline it times out, and both mean "nothing to announce".
///
/// It keeps asking after an update is found, and announces only the first
/// time: the daily request is also the one sign that a copy is still in use,
/// and standing down would erase everyone running a version they have not
/// updated yet.
@MainActor
final class UpdateChecker {
    static let automaticKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let feedURL = URL(string: "https://stillpane.dev/version.json")!
    /// How often the timer wakes, not how often anything is sent:
    /// `UpdateSchedule` holds the request itself to one a day, and every
    /// other wake returns without touching the network. A 24-hour timer is
    /// anchored to launch time, so it drifts past midnight and leaves a Mac
    /// that stayed up all day without a check.
    private static let pollInterval: TimeInterval = 6 * 60 * 60

    /// Default on; the menu toggle is the off switch.
    static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: automaticKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: automaticKey) }
    }

    private static var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckKey) }
    }

    private(set) var available: UpdateFeed.Info?
    var onUpdateAvailable: ((UpdateFeed.Info) -> Void)?
    private var timer: Timer?

    func start() {
        check()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.check() }
        }
        // The exact hour is irrelevant; letting the system coalesce the fire
        // keeps the check off battery-hostile wakeups.
        timer.tolerance = 60 * 60
        self.timer = timer
    }

    private func check() {
        guard Self.automatic, UpdateSchedule.isDue(last: Self.lastCheck, now: Date()) else { return }
        var request = URLRequest(url: Self.feedURL)
        request.setValue("stillpane/\(StillpaneVersion.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            // The day is spent once the request lands, whatever it answers: an
            // error page is a day accounted for, while a timeout leaves the
            // next poll free to try again.
            guard let http = response as? HTTPURLResponse else { return }
            Task { @MainActor in Self.lastCheck = Date() }
            guard let data,
                http.statusCode == 200,
                let info = UpdateFeed.parse(data),
                UpdateFeed.isNewer(info.version, than: StillpaneVersion.version)
            else { return }
            Task { @MainActor in
                guard let self, self.available != info else { return }
                self.available = info
                self.onUpdateAvailable?(info)
            }
        }.resume()
    }
}
