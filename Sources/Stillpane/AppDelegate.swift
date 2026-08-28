import AppKit
import ServiceManagement
import StillpaneCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var defaultModeItem: NSMenuItem?
    private var alternateModeItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var autoUpdateItem: NSMenuItem?
    private let hotkey = HotkeyMonitor()
    private let coordinator = CaptureCoordinator()
    private let updateChecker = UpdateChecker()

    /// Deliberately not persisted: a relaunch always starts active. A user
    /// who paused yesterday and forgot would otherwise report "capture
    /// stopped working".
    private var isPaused = false

    /// Hourly capture pruning while the app runs, so the 24-hour retention
    /// promise holds even when no further capture ever happens.
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstance.becomeOnlyInstance() else {
            SingleInstance.activateExisting()
            NSApp.terminate(nil)
            return
        }
        if AppPlacement.moveToApplicationsIfNeeded() { return }
        setUpStatusItem()
        registerLoginItemOnFirstLaunch()
        OnboardingWindow.showIfNeeded()
        // A global monitor installed by an untrusted process is dead for
        // this process's lifetime no matter when the grant lands.
        HotkeyHealth.needsRestart = !Permissions.accessibilityGranted
        hotkey.start { [weak self] shiftHeld in
            self?.performCapture(shiftHeld: shiftHeld)
        }
        // Launch-time root repair: captures and hook markers must never sit
        // under a permissive or replaced root left by anything else.
        _ = coordinator.preparedRootURL()
        coordinator.expireOldCaptures()
        let timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.coordinator.expireOldCaptures() }
        }
        timer.tolerance = 300
        expiryTimer = timer
        updateChecker.onUpdateAvailable = { [weak self] info in
            // Verb-first so the row reads as clickable: it opens the release
            // page for this version (the app never updates itself).
            let title = "Update to stillpane \(info.version)..."
            self?.updateItem?.title = title
            // The menu is the only update signal - the menu bar icon never
            // badges - so the row itself carries the alert color.
            self?.updateItem?.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor(red: 0.76, green: 0.30, blue: 0.30, alpha: 1.0),
                    .font: NSFont.menuFont(ofSize: 0),
                ]
            )
            self?.updateItem?.isHidden = false
        }
        updateChecker.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        healHotkeyIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        expiryTimer?.invalidate()
    }

    /// Coming back to Stillpane after a trip through System Settings, or opening
    /// the status menu, is the moment to notice a grant that arrived while the
    /// dead monitor was already installed. Failure leaves the flag set, so
    /// the setup status board keeps telling the truth and the next activation
    /// tries again.
    private func healHotkeyIfNeeded() {
        guard HotkeyHealth.needsRestart, Permissions.accessibilityGranted else { return }
        Relauncher.relaunch()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.image()
        item.button?.image?.accessibilityDescription = "stillpane"

        let menu = NSMenu()

        // Informational, not actionable: opening this menu makes Stillpane the
        // frontmost app, so there would be no window left to capture.
        let version = NSMenuItem(
            title: "stillpane \(StillpaneVersion.version)", action: nil, keyEquivalent: ""
        )
        version.isEnabled = false
        menu.addItem(version)

        // Hidden until the daily check finds a newer release; opens the
        // release page - the app never updates itself.
        let update = NSMenuItem(
            title: "Update Available...", action: #selector(openUpdate), keyEquivalent: ""
        )
        update.target = self
        update.isHidden = true
        menu.addItem(update)
        updateItem = update

        menu.addItem(.separator())

        // Each line binds a gesture to what it actually captures right now,
        // rather than naming a mode the reader then has to bind to a gesture
        // themselves. Swapping trades the two outcomes, so the block reads as
        // the truth either way round and the swap is visible in place.
        let defaultMode = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        defaultMode.isEnabled = false
        menu.addItem(defaultMode)
        defaultModeItem = defaultMode

        let alternateMode = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        alternateMode.isEnabled = false
        menu.addItem(alternateMode)
        alternateModeItem = alternateMode

        let swap = NSMenuItem(
            title: "Swap Capture Modes", action: #selector(swapCaptureModes), keyEquivalent: ""
        )
        swap.target = self
        menu.addItem(swap)
        refreshCaptureModeItems()

        menu.addItem(.separator())
        // One item, because "is my setup healthy?" and "walk me through
        // setup" are the same window now: it opens on the status board once
        // setup is done, and on the flow while it is not.
        let actionable = [
            NSMenuItem(title: "Setup", action: #selector(openSetup), keyEquivalent: ""),
            NSMenuItem(title: "Open Captures Folder", action: #selector(openCaptures), keyEquivalent: ""),
        ]
        for item in actionable {
            item.target = self
            menu.addItem(item)
        }

        let pause = NSMenuItem(
            title: "Pause Captures", action: #selector(togglePause), keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause

        let login = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        launchAtLoginItem = login

        let autoUpdate = NSMenuItem(
            title: "Check for Updates Automatically",
            action: #selector(toggleAutoUpdateCheck), keyEquivalent: ""
        )
        autoUpdate.target = self
        autoUpdate.state = UpdateChecker.automatic ? .on : .off
        menu.addItem(autoUpdate)
        autoUpdateItem = autoUpdate

        menu.addItem(.separator())
        let report = NSMenuItem(
            title: "Report a Problem...", action: #selector(reportProblem), keyEquivalent: ""
        )
        report.target = self
        menu.addItem(report)
        let uninstall = NSMenuItem(
            title: "Uninstall stillpane...", action: #selector(uninstallApp), keyEquivalent: ""
        )
        uninstall.target = self
        menu.addItem(uninstall)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit stillpane", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// The capture moment replaces the confirmation text on the happy path:
    /// the system shutter from `screencapture` and a white flash over the
    /// window that shrinks away toward the menu bar. The HUD stays for
    /// everything that has no picture to show - errors, and a text-only
    /// capture.
    private func performCapture(shiftHeld: Bool = false) {
        // While the rehearsal owns the chord, the pipeline stands down: the
        // overlay stages the whole capture moment itself, and a real capture
        // racing it would fire a second flash into the demo.
        guard !RehearsalOverlay.isActive else { return }
        // Paused means paused: no shutter, no flash, no files. The dimmed
        // menu bar icon is what explains the silence.
        guard !isPaused else { return }
        // A chord landing while stillpane itself is active - the setup window
        // after a rehearsal, say - would capture our own UI, which is never
        // what the user meant. Guidance beats a junk capture.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
        {
            HUD.flash("Switch to the window you want to capture, then press both Option keys")
            return
        }
        guard Permissions.accessibilityGranted else {
            HUD.flash("Grant Accessibility permission to capture")
            Permissions.openAccessibilitySettings()
            return
        }
        let mode = CaptureMode.resolve(
            defaultTextOnly: CaptureSettings.textOnly, shiftHeld: shiftHeld
        )
        let canScreenshot = mode.wantsScreenshot && Permissions.screenRecordingGranted
        // Only ask for the permission when this capture actually wants a
        // picture: prompting someone who just asked for text would be asking
        // for something they declined in the same keystroke. A user who chose
        // text-only captures during setup said no once already; re-prompting
        // on every capture would nag them out of it.
        if mode.wantsScreenshot, !Permissions.screenRecordingGranted,
            !OnboardingState.screenRecordingSkipped
        {
            Permissions.requestScreenRecording()
        }
        // The moment belongs to every capture, not just the ones with a
        // picture: a text capture is still a capture, and it lands in the
        // card as the shape of the text it took.
        coordinator.capture(includeScreenshot: canScreenshot) { target in
            if let frame = target.frame {
                CaptureFeedback.flash(windowFrame: frame)
            }
        } completion: { result in
            switch result {
            case .success(let input):
                if let pngData = input.pngData, let image = NSImage(data: pngData) {
                    CaptureFeedback.showThumbnail(image)
                } else if !CaptureFeedback.showTextCard() {
                    // No card to fill - the window reported no frame to fly
                    // from - so the confirmation has to be words.
                    HUD.flash("Captured (text only): \(input.app)")
                }
            case .failure(let error):
                CaptureFeedback.dismiss()
                HUD.flash(error.message)
            }
        }
    }

    @objc private func openSetup() {
        OnboardingWindow.showStatus()
    }

    /// Registered once, on first launch, so the app survives reboots by
    /// default. Registering only once means a later opt-out - in System
    /// Settings or via the menu - is never silently overridden. The flag is
    /// set only when registration succeeded: a failed attempt (a bare dev
    /// binary, say) must not burn the one shot the real install gets.
    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard (try? SMAppService.mainApp.register()) != nil else { return }
        UserDefaults.standard.set(true, forKey: key)
    }

    @objc private func swapCaptureModes() {
        CaptureSettings.textOnly.toggle()
        refreshCaptureModeItems()
    }

    private func refreshCaptureModeItems() {
        let textOnly = "Text only"
        let full = "Screenshot + text"
        let plainChord = CaptureSettings.textOnly ? textOnly : full
        defaultModeItem?.title = "Left + right Option: \(plainChord)"
        alternateModeItem?.title = "With Shift: \(CaptureSettings.textOnly ? full : textOnly)"
    }

    @objc private func togglePause() {
        isPaused.toggle()
        pauseItem?.state = isPaused ? .on : .off
        statusItem?.button?.appearsDisabled = isPaused
    }

    @objc private func openUpdate() {
        guard let info = updateChecker.available else { return }
        NSWorkspace.shared.open(info.url)
    }

    @objc private func toggleAutoUpdateCheck() {
        UpdateChecker.automatic.toggle()
        autoUpdateItem?.state = UpdateChecker.automatic ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            HUD.flash("Could not update Launch at Login")
        }
    }

    @objc private func reportProblem() {
        SetupReport.gather(accessibilityStatus: HotkeyHealth.accessibilityStatus) { report in
            SetupReport.openIssue(report: report)
        }
    }

    @objc private func uninstallApp() {
        // The chord dies with the confirm: a capture landing mid-teardown
        // would recreate the folders the uninstall just promised were gone.
        Uninstaller.confirmAndRun(
            stopCaptures: { [hotkey] in hotkey.stop() },
            captureRunning: { [coordinator] in coordinator.isBusy }
        )
    }

    @objc private func openCaptures() {
        guard let root = coordinator.preparedRootURL() else {
            HUD.flash("Could not open the captures folder")
            return
        }
        NSWorkspace.shared.open(root)
    }
}

/// Opening the status menu is the other reliable moment to notice a grant:
/// clicking the icon does not always activate the app.
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        healHotkeyIfNeeded()
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        // Cheap, and it keeps the two mode lines honest even if the default
        // was changed by something other than the swap item.
        refreshCaptureModeItems()
    }
}
