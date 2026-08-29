import AppKit
import StillpaneCore
import SwiftUI

/// The guided flow: one step on screen at a time, a progress indicator above
/// it, and an animated slide between them. `OnboardingState` decides which step
/// is current and performs every side effect; nothing here holds state of its
/// own beyond animation.
struct OnboardingView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if state.showingStatus {
                    SetupStatusView(state: state)
                } else {
                    stepBody
                        .id(state.step)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.42, dampingFraction: 0.88), value: state.step)
            .animation(.easeInOut(duration: 0.25), value: state.showingStatus)
            // Without this the outgoing step slides out through the window
            // edge instead of being cut off by it.
            .clipped()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
        .frame(minWidth: 640, minHeight: 520)
        .background(background)
    }

    /// Progress dots belong to the walkthrough. A step opened from the status
    /// board is not progress through anything, so that spot carries the way
    /// back instead.
    @ViewBuilder
    private var header: some View {
        if state.returnsToStatus {
            HStack {
                QuietLink("Back to Setup Status") { state.showStatus() }
                Spacer()
            }
            .padding(.top, 18)
            .padding(.bottom, 24)
        } else if !state.showingStatus {
            StepIndicator(current: state.step)
                .padding(.top, 18)
                .padding(.bottom, 24)
        } else {
            Color.clear.frame(height: 24)
        }
    }

    /// The void, and - on the finished step only - the aurora: the flow's one
    /// splash of colour, saved for the moment there is something to celebrate.
    private var background: some View {
        ZStack {
            VoidTheme.background
            // The aurora celebrates finishing setup. The board is a reading,
            // not a celebration, even though the flow behind it rests on
            // `.done`.
            if state.step == .done, !state.showingStatus {
                AuroraGlow().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.9), value: state.step)
        .clipped()
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var stepBody: some View {
        if state.revisitingHealthyStep {
            HealthyStep(state: state)
        } else {
            walkthroughStep
        }
    }

    @ViewBuilder
    private var walkthroughStep: some View {
        switch state.step {
        case .welcome: WelcomeStep(state: state)
        case .accessibility: AccessibilityStep(state: state)
        case .screenRecording: ScreenRecordingStep(state: state)
        case .claudeCode: ClaudeCodeStep(state: state)
        case .tryIt: TryItStep(state: state)
        case .done: DoneStep()
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 20) {
                // The wordmark, drawn from its generated outlines - identical
                // geometry to assets/wordmark.svg.
                WordmarkView()
                    .frame(height: 46)
                Text("Your window, in your next Claude Code message.")
                    .font(VoidTheme.body)
                    .foregroundStyle(VoidTheme.muted)
                    .multilineTextAlignment(.center)
            }
            WelcomeVisual()
                .padding(.vertical, 18)
            VStack(alignment: .leading, spacing: 14) {
                WelcomeBullet(
                    symbol: "option",
                    title: "Press both Option keys",
                    text: """
                        The window in front of you is captured: a screenshot, \
                        plus all of its text as agent-ready markdown - even what \
                        is scrolled out of view.
                        """
                )
                WelcomeBullet(
                    symbol: "paperclip",
                    title: "It attaches itself",
                    text: """
                        Your next Claude Code message carries the capture. \
                        Nothing to paste, nothing to describe.
                        """
                )
                WelcomeBullet(
                    symbol: "lock",
                    title: "Captured content stays local",
                    text: """
                        Your captures never reach us. stillpane keeps them on \
                        your Mac and has no server to upload them to. Attaching \
                        one to Claude Code sends its contents to your model \
                        provider, like anything else you type.
                        """
                )
            }
            .frame(maxWidth: 540)
            SpacebarButton(title: "Get Started", showsSpaceHint: true) {
                state.continueFromWelcome()
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
    }
}

/// One row of the welcome explainer: a glyph chip in the keycap idiom, a
/// scannable lead, and one line of detail under it.
private struct WelcomeBullet: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VoidTheme.ink)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VoidTheme.noteStrong)
                    .foregroundStyle(VoidTheme.ink)
                Text(text)
                    .font(VoidTheme.note)
                    .foregroundStyle(VoidTheme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// What a healthy step shows when it is opened from the status board. There
/// is nothing to do on it, so it says so and offers the way back rather than
/// asking again for a permission that was granted months ago.
private struct HealthyStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        StepCard(symbol: "checkmark.circle.fill", title: state.step.title, sentence: sentence) {
            ForEach(Array(state.statusItems(for: state.step).enumerated()), id: \.offset) { _, item in
                StepNote("\(item.name): \(item.detail)")
            }
            SpacebarButton(title: "Back to Setup Status") { state.showStatus() }
        }
    }

    private var sentence: String {
        switch state.step {
        case .accessibility:
            return "stillpane can read window text, so captures carry everything the window holds."
        case .screenRecording:
            return "stillpane can take the screenshot, so captures carry the picture as well as the text."
        case .claudeCode:
            return "The plugin is installed, so captures attach to your Claude Code messages."
        case .welcome, .tryIt, .done:
            return "This part of setup is done."
        }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var state: OnboardingState

    /// The stale-row recovery surfaces only after the grant has kept us
    /// waiting well past a normal trip through System Settings: its audience
    /// is the user whose pane says enabled while nothing happens, and anyone
    /// else would read a "still not working?" link as a bad omen.
    @State private var showSelfHeal = false

    /// Arriving from the status board, the evidence the rescues wait for is
    /// already in: the board said this is broken, which is why the user
    /// clicked it. Making them re-earn a 20-second timer would be theatre.
    private var earned: Bool { state.returnsToStatus || state.didRequestAccessibility }

    var body: some View {
        StepCard(
            symbol: "accessibility",
            title: "Let stillpane read window text",
            sentence: """
                Accessibility permission is how a capture picks up the text of the \
                window, including everything scrolled out of view.
                """
        ) {
            SpacebarButton(title: "Allow Accessibility") { state.requestAccessibility() }
                .task(id: state.didRequestAccessibility) {
                    guard state.didRequestAccessibility, !showSelfHeal else { return }
                    try? await Task.sleep(for: .seconds(20))
                    withAnimation { showSelfHeal = true }
                }

            if let message = state.accessibilityMessage {
                StepNote(message)
            } else {
                WaitingLabel(text: "Waiting for the grant. stillpane restarts itself once it lands.")
            }

            if earned {
                QuietLink("No prompt appeared? Open System Settings") {
                    state.openAccessibilitySettings()
                }
            }

            if earned, showSelfHeal || state.returnsToStatus {
                QuietLink("Enabled in Settings but nothing happens? Reset and grant fresh") {
                    state.selfHealAccessibility()
                }
                .transition(.opacity)
            }
        }
    }
}

private struct ScreenRecordingStep: View {
    @ObservedObject var state: OnboardingState

    /// The rescue links surface one at a time, each earned by evidence: in
    /// the happy path the probe notices the grant and the app restarts itself
    /// within seconds, so a fresh spinner over a wall of underlined escape
    /// hatches would read as trouble before any trouble existed.
    @State private var showRescues = false
    /// The stale-row recovery arrives last: its audience is the user whose
    /// pane says enabled while the probe keeps saying no.
    @State private var showSelfHeal = false

    /// Same reasoning as the Accessibility step: a visit from the status
    /// board arrives with the evidence already in hand.
    private var earned: Bool { state.returnsToStatus || state.didRequestScreenRecording }

    var body: some View {
        StepCard(
            symbol: "photo.on.rectangle",
            title: "Let stillpane take the screenshot",
            sentence: "This lets stillpane take the screenshot. Without it, captures are text only."
        ) {
            SpacebarButton(title: "Allow Screen Recording") { state.requestScreenRecording() }
                .task(id: state.didRequestScreenRecording) {
                    guard state.didRequestScreenRecording, !showSelfHeal else { return }
                    if !showRescues {
                        try? await Task.sleep(for: .seconds(8))
                        withAnimation { showRescues = true }
                    }
                    try? await Task.sleep(for: .seconds(12))
                    withAnimation { showSelfHeal = true }
                }

            if let message = state.screenRecordingMessage {
                StepNote(message)
            } else {
                WaitingLabel(text: "Waiting for the grant. stillpane restarts itself once it lands.")
            }

            if earned, showRescues || state.returnsToStatus {
                QuietLink("No prompt appeared? Open System Settings") {
                    state.openScreenRecordingSettings()
                }
                .transition(.opacity)
            }

            if earned, showSelfHeal || state.returnsToStatus {
                QuietLink("Enabled in Settings but nothing happens? Reset and grant fresh") {
                    state.selfHealScreenRecording()
                }
                .transition(.opacity)
            }

            QuietLink("Continue without screenshots - captures carry text only") {
                state.skipScreenRecording()
            }
        }
    }
}

private struct ClaudeCodeStep: View {
    @ObservedObject var state: OnboardingState

    private var isLocating: Bool {
        state.isWorking && state.claudePath == nil && state.cliSetupStatus == nil
    }

    var body: some View {
        StepCard(
            symbol: "puzzlepiece.extension",
            title: "Connect Claude Code",
            sentence: sentence,
            contentWidth: 500
        ) {
            if isLocating {
                WaitingLabel(text: "Looking for the claude command")
            } else if state.claudePath == nil {
                if state.claudeAppPresent {
                    SpacebarButton(title: "Install Plugin", isEnabled: !state.isWorking) {
                        state.installClaudeCode()
                    }
                    .overlay(alignment: .trailing) {
                        if state.isWorking {
                            ProgressView().controlSize(.small).offset(x: 30)
                        }
                    }
                    if let status = state.cliSetupStatus {
                        if let fraction = state.cliDownloadProgress {
                            DownloadMeter(text: status, fraction: fraction)
                            QuietLink("Cancel") { state.cancelCLIDownload() }
                        } else {
                            WaitingLabel(text: status)
                        }
                    }
                    if state.awaitingDeveloperTools {
                        QuietLink("Stop waiting") { state.cancelCLISetup() }
                    }
                    if !state.isWorking {
                        QuietLink("Prefer the Terminal? Copy the install command") {
                            state.copyCLIInstallCommand()
                        }
                        QuietLink("Check Again") { state.retryClaudeDetection() }
                    }
                } else {
                    HStack(spacing: 10) {
                        Button("Install Claude Code") { state.openClaudeCodeSite() }
                            .buttonStyle(.voidProminent)
                        Button("Check Again") { state.retryClaudeDetection() }
                            .buttonStyle(.voidQuiet)
                    }
                    StepNote(
                        """
                        Already using Claude Code? The claude command is just not on \
                        this Mac's usual paths - run these two lines in a Claude \
                        Code terminal session instead.
                        """)
                    Text(ClaudeCLI.installCommands)
                        .font(VoidTheme.mono)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    Button("Copy Commands") { state.copyInstallCommands() }
                        .buttonStyle(.voidQuiet)
                }
            } else if !state.pluginInstalled {
                // Once installed the button disappears entirely: a greyed
                // "Installed" control is a dead weight over the state line.
                // The spinner floats in an overlay so its appearance never
                // shifts the button: elements stay where the eye left them.
                SpacebarButton(title: "Install Plugin", isEnabled: !state.isWorking) {
                    state.connectClaudeCode()
                }
                .overlay(alignment: .trailing) {
                    if state.isWorking {
                        ProgressView().controlSize(.small).offset(x: 30)
                    }
                }
                // The one-press chain sets `claudePath` before its last leg,
                // which lands the view here; the narration follows it.
                if let status = state.cliSetupStatus {
                    WaitingLabel(text: status)
                }
            }

            if let message = state.claudeMessage {
                StepNote(message)
                if state.claudeMessageIsError {
                    QuietLink("Report this issue") { state.reportClaudeInstallIssue() }
                }
            }

            // Advancing with no plugin would rehearse a capture that cannot
            // attach. The plugin is the product, so there is no way past this
            // step without it - Continue only exists once the install landed.
            if state.pluginInstalled {
                SpacebarButton(title: "Continue") { state.continueFromClaudeCode() }
            }
        }
    }

    private var sentence: String {
        if isLocating {
            return "stillpane attaches captures through a Claude Code plugin."
        }
        if state.claudePath == nil {
            if state.claudeAppPresent {
                return """
                    stillpane attaches captures through a Claude Code plugin, and \
                    this installs it for you, along with the claude command line tool.
                    """
            }
            return """
                stillpane attaches captures through a Claude Code plugin, but the \
                claude command line tool does not seem to be installed on this Mac. \
                Install Claude Code first, then come back - setup continues right here.
                """
        }
        return "stillpane attaches captures through a Claude Code plugin, and this installs it for you."
    }
}

/// The visible half of the try-it step. The step normally plays out as the
/// full-screen rehearsal; this body is what a cancel comes back to, and the
/// capture poll keeps running either way.
private struct TryItStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        StepCard(
            symbol: "keyboard",
            title: "Take your first capture",
            sentence: """
                Switch to any app and press left Option and right Option together; \
                leave this window open and it moves on by itself once a capture lands.
                """
        ) {
            WaitingLabel(text: "Waiting for a capture")
            QuietLink("Show the full-screen guide again") { state.startRehearsal() }
        }
    }
}

private struct DoneStep: View {
    var body: some View {
        StepCard(
            symbol: "checkmark.circle.fill",
            title: "You are set up",
            sentence: """
                Press left Option and right Option in any app to capture it, or \
                add Shift to capture its text without a screenshot; captures older \
                than 24 hours are deleted automatically.
                """
        ) {
            // The plugin loads when a session starts, so a session that was
            // already open during setup will never see a capture; saying so
            // here is the difference between "start a new session" and "it
            // doesn't work".
            StepNote(
                "Already have a Claude Code session open? Captures only attach in sessions started after this setup.")
            SpacebarButton(title: "Close") { OnboardingWindow.close() }
            StepNote("Reopen this window any time from the menu bar icon.")
        }
    }
}

// MARK: - Pieces

/// One icon, one title, one sentence, then whatever the step needs the user to
/// do. Every step but the welcome screen wears this shape, which is what makes
/// the flow read as a flow. The glyph stands alone in the void - no chrome
/// around it.
private struct StepCard<Actions: View>: View {
    let symbol: String
    let title: String
    let sentence: String
    var contentWidth: CGFloat = 440
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(VoidTheme.ink)
            // Title and sentence read as one thought; the wider gaps separate
            // them from the glyph above and the actions below.
            VStack(spacing: 12) {
                Text(title)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(VoidTheme.ink)
                Text(sentence)
                    .font(VoidTheme.body)
                    .foregroundStyle(VoidTheme.muted)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 16) { actions }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity)
    }
}

private struct StepIndicator: View {
    let current: OnboardingStep

    private var steps: [OnboardingStep] { OnboardingStep.indicatorSteps }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(steps) { step in
                Capsule()
                    .fill(color(for: step))
                    .frame(width: step == current ? 26 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
        .accessibilityElement()
        .accessibilityLabel(
            "Step \(min(current.indicatorIndex + 1, steps.count)) of \(steps.count): \(current.title)"
        )
    }

    private func color(for step: OnboardingStep) -> Color {
        if step == current { return VoidTheme.ink }
        if current.isPast(step) { return VoidTheme.ink.opacity(0.45) }
        return Color.white.opacity(0.18)
    }
}

/// A quiet recovery path: real, reachable, and visibly not the thing to click
/// first. Shared with the status board, which uses it for the walkthrough.
struct QuietLink: View {
    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        // Small, but underlined: a recovery path nobody can tell is clickable
        // is not a recovery path. Muted rather than link-blue, so it still
        // loses to the prominent button.
        Button(action: action) {
            Text(title)
                .font(VoidTheme.note)
                .underline()
                .foregroundStyle(VoidTheme.muted)
                // Links long enough to wrap stay centered like everything
                // else in the step column.
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
        // A link that keeps the arrow cursor reads as plain text; the hand
        // is what says "clickable" before anyone commits to a click.
        .pointingHandOnHover()
    }
}

private struct StepNote: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(VoidTheme.note)
            .foregroundStyle(VoidTheme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WaitingLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(VoidTheme.note).foregroundStyle(VoidTheme.muted)
        }
    }
}

/// The download leg's determinate row: the waiting label's seat, a mono
/// percent at the line's end, and a hairline underneath. It replaces the
/// spinner - two progress indicators for one wait is noise.
private struct DownloadMeter: View {
    let text: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(text).font(VoidTheme.note).foregroundStyle(VoidTheme.muted)
                Spacer(minLength: 16)
                Text("\(Int(fraction * 100))%")
                    .font(VoidTheme.mono)
                    .monospacedDigit()
                    .foregroundStyle(VoidTheme.faint)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: max(geometry.size.width * fraction, 2))
                }
            }
            .frame(height: 2)
        }
        .frame(maxWidth: .infinity)
        .animation(.linear(duration: 0.2), value: fraction)
    }
}

/// Warmth kept in reserve: two soft colour fields rising from the bottom edge,
/// the capture flash held in suspension. Only the finished step wears it.
private struct AuroraGlow: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Ellipse()
                    .fill(VoidTheme.auraPink.opacity(0.4))
                    .frame(width: size.width * 0.9, height: size.height * 0.55)
                    .offset(x: -size.width * 0.18, y: size.height * 0.6)
                Ellipse()
                    .fill(VoidTheme.auraViolet.opacity(0.32))
                    .frame(width: size.width * 0.9, height: size.height * 0.55)
                    .offset(x: size.width * 0.22, y: size.height * 0.66)
            }
            .frame(width: size.width, height: size.height)
            .blur(radius: 60)
        }
        .allowsHitTesting(false)
    }
}
