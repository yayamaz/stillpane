import AppKit
import StillpaneCore

/// Drives the setup assistant: which step is current, what the live system
/// state says, and the side effects each step performs.
///
/// Steps are derived from live checks rather than from stored progress, so a
/// permission revoked later reopens the assistant on exactly that step.
@MainActor
final class OnboardingState: ObservableObject {
    private static let completedKey = "onboardingCompleted"
    /// Set when the user leaves the welcome screen. The Accessibility and
    /// Screen Recording steps both restart the app, and the relaunched process
    /// needs to know the pitch was already made.
    private static let sawWelcomeKey = "onboardingSawWelcome"
    /// Set while the assistant is open and unfinished. Setup restarts the app
    /// twice (both permission steps), and System Settings offers its own Quit
    /// & Reopen; whichever way the process comes back, an unfinished
    /// walkthrough must come back with it, window on screen.
    private static let inProgressKey = "onboardingInProgress"
    /// Set when the user chooses text-only captures on the Screen Recording
    /// step. A deliberate skip must not read as "setup incomplete" - without
    /// this, every launch reopens the assistant on the step they declined.
    private static let skippedScreenRecordingKey = "screenRecordingSkipped"

    static var screenRecordingSkipped: Bool {
        UserDefaults.standard.bool(forKey: skippedScreenRecordingKey)
    }

    static var isInProgress: Bool {
        UserDefaults.standard.bool(forKey: inProgressKey)
    }

    @Published private(set) var step: OnboardingStep
    @Published private(set) var claudePath: URL?
    @Published private(set) var claudeMessage: String?
    /// True when `claudeMessage` reports a failure, so the step can offer a
    /// way to report it instead of dead-ending.
    @Published private(set) var claudeMessageIsError = false
    @Published private(set) var accessibilityMessage: String?
    @Published private(set) var screenRecordingMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var pluginInstalled = false
    /// True when the Claude desktop app is installed. It decides how the
    /// Claude Code step reads a missing `claude` command: such a Mac has
    /// Claude Code already, and only the command line tool is absent, so the
    /// step offers to add it rather than claiming Claude Code is missing.
    @Published private(set) var claudeAppPresent = false
    /// What the one-press install is doing right now, shown as the step's
    /// waiting label; nil when it is not running.
    @Published private(set) var cliSetupStatus: String?
    /// True while the step waits for the OS's Command Line Tools install,
    /// which ends with no notification; the tick polls for it.
    @Published private(set) var awaitingDeveloperTools = false

    /// The status board: the window's root once setup is finished, listing
    /// every link in the chain and letting a broken one be opened at the step
    /// that repairs it.
    @Published private(set) var showingStatus: Bool
    @Published private(set) var statusItems: [SetupItem] = []
    /// True while a step is being visited from the board rather than walked
    /// as part of setup. It is the one difference between the two journeys:
    /// finishing the step returns to the board instead of moving on through a
    /// flow the user already completed.
    @Published private(set) var returnsToStatus = false
    /// True when the step opened from the board was already healthy. Such a
    /// visit is a look rather than a repair, so the step shows what is working
    /// instead of asking for a permission that is already granted, and the
    /// poll stays out of it - the Accessibility poll would otherwise read the
    /// live grant and relaunch the app out from under the reader.
    @Published private(set) var revisitingHealthyStep = false

    /// Whether the user has asked for each permission yet. The recovery
    /// affordances (open System Settings by hand, restart to clear a stale
    /// grant) only make sense once the ordinary path has been tried, and
    /// showing them to a fresh user would just be noise.
    @Published private(set) var didRequestAccessibility = false
    @Published private(set) var didRequestScreenRecording = false

    /// TCC publishes no grant notification, so the only way to notice a grant
    /// is to ask again. One second is imperceptible next to a trip through
    /// System Settings and costs nothing measurable while the window is open.
    private static let pollInterval: TimeInterval = 1
    /// The Screen Recording check spawns a probe process (the in-process
    /// answer is cached, see `Permissions.probeScreenRecording`), so it runs
    /// on a gentler cadence than the free in-process ticks.
    private static let screenProbeInterval: TimeInterval = 2
    /// The Command Line Tools probe spawns a process, so it runs on its own
    /// gentler cadence, like the Screen Recording probe.
    private static let developerToolsProbeInterval: TimeInterval = 3
    private var timer: Timer?
    private var captureBaseline: Date?
    private var screenProbeInFlight = false
    private var lastScreenProbe: Date = .distantPast
    private var developerToolsProbeInFlight = false
    private var lastDeveloperToolsProbe: Date = .distantPast

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Checks that cost nothing. Plugin detection spawns a process, so it runs
    /// separately and asynchronously.
    static var needsOnboardingByLocalChecks: Bool {
        !Permissions.accessibilityGranted
            || (!Permissions.screenRecordingGranted && !screenRecordingSkipped)
            || !isCompleted
    }

    /// The welcome screen fronts a first run - it is the screen that says what
    /// Stillpane is, and a permission prompt with no introduction is how setup
    /// flows lose people. Every later arrival resumes where the work is: a
    /// mid-setup relaunch on the next incomplete step, a finished install
    /// reopened to repair one permission on that permission.
    /// `startOnStatus` is the menu's entry: a finished install reopened by
    /// hand is asking "is everything still working?", which the board answers
    /// and the flow does not. Automatic opens leave it false and keep landing
    /// straight on the broken step, because there is exactly one thing wrong
    /// and the board would only add a click.
    init(startOnStatus: Bool = false) {
        let isFirstRun =
            !Self.isCompleted
            && !UserDefaults.standard.bool(forKey: Self.sawWelcomeKey)
        step = isFirstRun ? .welcome : Self.firstIncompleteLocalStep()
        showingStatus = startOnStatus && Self.isCompleted
    }

    private static func firstIncompleteLocalStep() -> OnboardingStep {
        if !Permissions.accessibilityGranted { return .accessibility }
        if !Permissions.screenRecordingGranted, !screenRecordingSkipped { return .screenRecording }
        return .claudeCode
    }

    // MARK: - Lifecycle

    /// True only while walking setup for real. The board and a step visited
    /// from it both look like a current step to the rest of this type, but
    /// neither should be carried forward to the next one.
    private var isWalkingFlow: Bool { !showingStatus && !returnsToStatus }

    func start() {
        // The in-progress flag exists to reopen an unfinished walkthrough at
        // the next launch. A finished install reading its own status is not
        // that, and marking it so would reopen this window forever - nothing
        // clears the flag but reaching Done, which the board never does.
        if !Self.isCompleted {
            UserDefaults.standard.set(true, forKey: Self.inProgressKey)
        }
        if showingStatus { refreshStatus() }
        detectClaude()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop, so this always fires on the main thread.
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One background pass finds the binary and asks whether the plugin is
    /// already there, so a user who installed it earlier never sees the step.
    private func detectClaude() {
        isWorking = true
        claudeAppPresent =
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
        ClaudeCLI.detectInBackground { [weak self] detection in
            guard let self else { return }
            self.isWorking = false
            self.claudePath = detection.path
            self.pluginInstalled = detection.pluginInstalled
            if detection.pluginInstalled, self.step == .claudeCode, self.isWalkingFlow {
                self.advance()
            }
        }
    }

    // MARK: - Polling

    private func tick() {
        // The board is a reading, not a step, and so is a look at a step that
        // is already healthy: neither should relaunch the app or move the
        // flow along under the user.
        guard !showingStatus, !revisitingHealthyStep else { return }
        switch step {
        case .accessibility:
            // Once the manual message is showing, the relaunch already failed;
            // retrying it every second would spawn `open` on a loop.
            if Permissions.accessibilityGranted, accessibilityMessage == nil {
                relaunchForAccessibility()
            }
        case .screenRecording:
            if Permissions.screenRecordingGranted {
                advance()
            } else {
                probeScreenRecording()
            }
        case .claudeCode:
            pollDeveloperTools()
        case .tryIt:
            if hasNewCapture() { advance() }
        case .welcome, .done:
            break
        }
    }

    /// Waits out the OS's Command Line Tools install after
    /// `installClaudeCode` requested it. The install runs in Apple's own UI
    /// and finishes silently, so noticing it means asking again.
    private func pollDeveloperTools() {
        guard awaitingDeveloperTools, !developerToolsProbeInFlight,
            Date().timeIntervalSince(lastDeveloperToolsProbe) >= Self.developerToolsProbeInterval
        else { return }
        developerToolsProbeInFlight = true
        lastDeveloperToolsProbe = Date()
        DispatchQueue.global(qos: .utility).async {
            let present = ClaudeCLIInstaller.developerToolsPresent()
            Task { @MainActor in
                self.developerToolsProbeInFlight = false
                guard present, self.awaitingDeveloperTools, self.step == .claudeCode else { return }
                self.installCLIAndPlugin()
            }
        }
    }

    /// The relaunch itself lives in `Relauncher`, because AppDelegate needs the
    /// same mechanism for a grant that arrives with no assistant window open.
    /// Stopping the timer before terminating keeps a cancelled termination from
    /// letting the next tick spawn a second copy.
    private func relaunchForAccessibility() {
        switch Relauncher.relaunch(beforeTerminating: { [weak self] in self?.stop() }) {
        case nil: break
        case .notABundle: advance()
        case .openFailed: accessibilityMessage = Relauncher.manualRelaunchMessage
        }
    }

    /// The out-of-process grant check that makes the step self-sufficient: a
    /// fresh probe process sees the grant the moment it lands, so the app
    /// restarts itself instead of waiting for macOS's optional Quit & Reopen
    /// popup or asking the user to claim they granted it. Once the manual
    /// message is showing, a relaunch already failed; auto-retrying it would
    /// spawn `open` on a loop.
    private func probeScreenRecording() {
        guard screenRecordingMessage == nil, !screenProbeInFlight,
            Date().timeIntervalSince(lastScreenProbe) >= Self.screenProbeInterval
        else { return }
        screenProbeInFlight = true
        lastScreenProbe = Date()
        Permissions.probeScreenRecording { granted in
            // Permissions delivers this on the main thread.
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.screenProbeInFlight = false
                guard granted, self.step == .screenRecording, self.screenRecordingMessage == nil
                else { return }
                self.restartForScreenRecording()
            }
        }
    }

    private func hasNewCapture() -> Bool {
        guard let baseline = captureBaseline else { return false }
        guard let newest = Self.newestCaptureDate() else { return false }
        return newest > baseline
    }

    private static func newestCaptureDate() -> Date? {
        let root = CaptureStore.defaultRootURL
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey]
            )
        else { return nil }
        return entries.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
    }

    // MARK: - Step actions

    /// Leaving the welcome screen skips whatever is already in place, so a
    /// second run does not stop on a permission the user granted last time.
    /// Going through `firstIncompleteLocalStep` rather than plain `next` also
    /// keeps the flow off an already-granted Accessibility step, where the poll
    /// would immediately relaunch the app.
    func continueFromWelcome() {
        guard step == .welcome else { return }
        UserDefaults.standard.set(true, forKey: Self.sawWelcomeKey)
        enter(Self.firstIncompleteLocalStep())
    }

    /// One surface at a time: the OS prompt, whose own button opens System
    /// Settings. Opening the pane ourselves as well would put two competing
    /// windows on screen, and opening it *instead* would cost the
    /// registration the prompt API performs - a first run can otherwise
    /// reach a pane that does not list Stillpane at all.
    func requestAccessibility() {
        didRequestAccessibility = true
        Permissions.requestAccessibility()
    }

    /// The fallback for when the OS prompt never appears: macOS shows it once
    /// per process, and not at all once the app has been denied.
    func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    func requestScreenRecording() {
        didRequestScreenRecording = true
        Permissions.requestScreenRecording()
    }

    func openScreenRecordingSettings() {
        Permissions.openScreenRecordingSettings()
    }

    /// Text-only captures are a legitimate way to run stillpane, not a
    /// half-finished setup: the skip also silences the permission request a
    /// capture would otherwise make. Granting later via System Settings
    /// upgrades captures without touching this flag, because the grant check
    /// always wins.
    func skipScreenRecording() {
        guard step == .screenRecording else { return }
        UserDefaults.standard.set(true, forKey: Self.skippedScreenRecordingKey)
        advance()
    }

    /// `CGPreflightScreenCaptureAccess` is answered from a per-process cache,
    /// so a grant that lands mid-run never flips it and the step would wait
    /// forever. macOS usually offers its own "Quit & Reopen", but not always -
    /// a stale TCC row from a rebuild, or the user picking "Later", both leave
    /// the app stuck - so the step offers the restart itself.
    func restartForScreenRecording() {
        switch Relauncher.relaunch(beforeTerminating: { [weak self] in self?.stop() }) {
        case nil:
            break
        case .notABundle, .openFailed:
            screenRecordingMessage =
                "Quit stillpane from the menu bar icon and open it again to pick up the grant."
        }
    }

    /// The stale-row recovery. A TCC row created by a differently-signed
    /// build shows as enabled in System Settings while the live check stays
    /// false, and the pane's toggle only re-approves the dead identity.
    /// Removing the row and restarting lets the fresh process register and
    /// prompt cleanly; the assistant resumes on the same step.
    func selfHealAccessibility() {
        Permissions.resetPermissionRecord(service: Permissions.accessibilityService)
        switch Relauncher.relaunch(beforeTerminating: { [weak self] in self?.stop() }) {
        case nil:
            break
        case .notABundle, .openFailed:
            accessibilityMessage =
                "Permission record reset. Quit stillpane from the menu bar and open it again, then grant Accessibility fresh."
        }
    }

    func selfHealScreenRecording() {
        Permissions.resetPermissionRecord(service: Permissions.screenRecordingService)
        switch Relauncher.relaunch(beforeTerminating: { [weak self] in self?.stop() }) {
        case nil:
            break
        case .notABundle, .openFailed:
            screenRecordingMessage =
                "Permission record reset. Quit stillpane from the menu bar and open it again, then grant Screen Recording fresh."
        }
    }

    func connectClaudeCode() {
        guard let claudePath, !isWorking else { return }
        isWorking = true
        claudeMessage = nil
        claudeMessageIsError = false
        installPlugin(with: claudePath)
    }

    /// The one-press path for a Mac with the Claude app but no `claude`
    /// command: add the command line tool, then install the plugin, landing
    /// in the same state the two-step path does. When git is missing the
    /// chain starts by requesting the OS's Command Line Tools install,
    /// because Claude Code's plugin commands shell out to git and fail
    /// without it; the tick's poll resumes the chain once the tools land.
    func installClaudeCode() {
        guard claudePath == nil, !isWorking else { return }
        isWorking = true
        claudeMessage = nil
        claudeMessageIsError = false
        cliSetupStatus = "Checking this Mac's tools…"
        DispatchQueue.global(qos: .userInitiated).async {
            if ClaudeCLIInstaller.developerToolsPresent() {
                Task { @MainActor in self.installCLIAndPlugin() }
                return
            }
            ClaudeCLIInstaller.requestDeveloperTools()
            Task { @MainActor in
                self.awaitingDeveloperTools = true
                self.cliSetupStatus = """
                    macOS is asking to install Apple's command line developer tools. \
                    Click Install in that dialog; setup continues on its own once they land.
                    """
            }
        }
    }

    /// The way out of the Command Line Tools wait, for a user who dismissed
    /// the OS dialog instead.
    func cancelCLISetup() {
        guard awaitingDeveloperTools else { return }
        awaitingDeveloperTools = false
        isWorking = false
        cliSetupStatus = nil
    }

    private func installCLIAndPlugin() {
        awaitingDeveloperTools = false
        cliSetupStatus = "Adding Claude Code's command line tool…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ClaudeCLIInstaller.install()
            Task { @MainActor in
                switch result {
                case .installed(let claude):
                    self.claudePath = claude
                    self.cliSetupStatus = "Installing the stillpane plugin…"
                    self.installPlugin(with: claude)
                case .failed(let message):
                    self.isWorking = false
                    self.cliSetupStatus = nil
                    self.claudeMessage = message
                    self.claudeMessageIsError = true
                }
            }
        }
    }

    /// The shared tail of both install paths. Expects `isWorking` to be set
    /// and clears it, along with the progress label, when the result lands.
    private func installPlugin(with claude: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ClaudeCLI.installPlugin(claude)
            Task { @MainActor in
                self.isWorking = false
                self.cliSetupStatus = nil
                self.pluginInstalled = result.succeeded
                self.claudeMessage =
                    result.succeeded
                    ? "Plugin installed."
                    : "Install did not complete: \(result.failureMessage)"
                self.claudeMessageIsError = !result.succeeded
            }
        }
    }

    func copyCLIInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ClaudeCLIInstaller.terminalCommand, forType: .string)
        HUD.flash("Command copied")
    }

    /// A failed install should not dead-end: this opens the prefilled GitHub
    /// issue with the failure message included.
    func reportClaudeInstallIssue() {
        SetupReport.gather(
            accessibilityStatus: Permissions.accessibilityGranted ? "granted" : "missing"
        ) { [weak self] report in
            SetupReport.openIssue(report: report, detail: self?.claudeMessage)
        }
    }

    /// The "I installed it - check again" path: one more locate + plugin
    /// probe, exactly like the one `start()` ran.
    func retryClaudeDetection() {
        guard !isWorking else { return }
        detectClaude()
    }

    func openClaudeCodeSite() {
        guard let url = URL(string: "https://claude.com/claude-code") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyInstallCommands() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ClaudeCLI.installCommands, forType: .string)
        HUD.flash("Commands copied")
    }

    func continueFromClaudeCode() {
        advance()
    }

    /// The rehearsal starts itself on arriving at the try-it step; this is the
    /// way back in after a cancel.
    func startRehearsal() {
        guard step == .tryIt else { return }
        OnboardingWindow.beginRehearsal()
    }

    /// The rehearsal's staged capture stands in for a real one: landing the
    /// chord there is what completes setup. The capture poll stays as the
    /// other way through, for a user who cancelled the rehearsal and takes a
    /// real capture from the window instead.
    func completeRehearsal() {
        guard step == .tryIt else { return }
        advance()
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        UserDefaults.standard.removeObject(forKey: Self.inProgressKey)
        stop()
    }

    // MARK: - Status board

    /// Shows the board and re-reads every check, so a repair made in the step
    /// just left is reflected the moment the user gets back.
    func showStatus() {
        returnsToStatus = false
        revisitingHealthyStep = false
        showingStatus = true
        refreshStatus()
    }

    func refreshStatus() {
        SetupReport.gatherItems(accessibilityStatus: HotkeyHealth.accessibilityStatus) {
            [weak self] items in
            self?.statusItems = items
        }
    }

    /// Opens the step that repairs a board row. The step behaves exactly as it
    /// does during setup, controls and self-healing included; only where it
    /// leads afterwards differs.
    func openStep(_ step: OnboardingStep) {
        returnsToStatus = true
        revisitingHealthyStep = isHealthy(step)
        showingStatus = false
        enter(step)
    }

    /// The board's way back to the walkthrough, which is otherwise
    /// unreachable once setup is done.
    func replayWalkthrough() {
        returnsToStatus = true
        revisitingHealthyStep = false
        showingStatus = false
        enter(.tryIt)
    }

    /// A step is healthy when every row it owns is. The Claude Code step owns
    /// two - the binary and the plugin - and a missing either way is a repair.
    private func isHealthy(_ step: OnboardingStep) -> Bool {
        let owned = statusItems.filter { $0.step == step }
        return !owned.isEmpty && owned.allSatisfy { $0.health == .ok }
    }

    /// The board rows a step owns, for the screen that reports what is
    /// already working.
    func statusItems(for step: OnboardingStep) -> [SetupItem] {
        statusItems.filter { $0.step == step }
    }

    private func advance() {
        // A step opened from the board has nowhere to advance to: the user
        // finished setup long ago and came back to repair one thing. A
        // replayed walkthrough ends here too, so the overlay comes down the
        // same way reaching `.done` takes it down.
        if returnsToStatus {
            OnboardingWindow.endRehearsal()
            showStatus()
            return
        }
        guard var next = step.next else { return }
        // Someone reopening a finished setup from the menu does not need to be
        // asked for another capture.
        if next == .tryIt, Self.isCompleted { next = .done }
        enter(next)
    }

    /// The one place a step becomes current, so every arrival - from the
    /// welcome screen, from a poll, from a button - runs the same side effects.
    private func enter(_ next: OnboardingStep) {
        step = next
        switch next {
        case .claudeCode:
            // Skipping a healthy step is right when walking the flow and
            // wrong when the user clicked that very row to look at it.
            if pluginInstalled, !returnsToStatus { advance() }
        case .tryIt:
            captureBaseline = Self.newestCaptureDate() ?? .distantPast
            OnboardingWindow.beginRehearsal()
        case .done:
            // The first capture usually lands while the rehearsal has the
            // screen; the window has to come back before it can celebrate.
            OnboardingWindow.endRehearsal()
            finish()
        case .welcome, .accessibility, .screenRecording:
            break
        }
    }
}
