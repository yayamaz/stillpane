import AppKit
import StillpaneCore
import SwiftUI

/// The first-capture rehearsal: every screen dims, and the screen that held
/// the setup window shows two mechanical Option keycaps that mirror the user's
/// real keys - hold left Option and the left cap goes down. Landing the chord
/// plays the whole capture moment as a staged demo with the real
/// choreography: the system shutter, a flash, a white card standing in for
/// the captured window flying up to the thumbnail rect under the menu bar and
/// becoming a canned shot, and a completion message. Nothing is actually
/// captured - AppDelegate stands the real pipeline down while the rehearsal
/// is active - so the demo needs no eligible window in front and cannot
/// half-work.
///
/// The overlay listens for the chord itself, with local monitors alongside the
/// global ones: global monitors never see the app's own events, and after the
/// setup window hides, Stillpane may well still be the active app.
@MainActor
enum RehearsalOverlay {
    private static let fadeDuration: TimeInterval = 0.25
    private static let escapeKeyCode: UInt16 = 53

    private static var panels: [NSPanel] = []
    private static var monitors: [Any] = []
    private static var model: RehearsalModel?
    private static var detector = ChordDetector()

    static var isActive: Bool { !panels.isEmpty }

    static func show(
        onCancel: @escaping @MainActor () -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) {
        dismiss(animated: false)

        let model = RehearsalModel(onCancel: onCancel, onComplete: onComplete)
        self.model = model
        detector = ChordDetector()

        // Resolved before the setup window hides, so the chord lesson lands on
        // the screen the user was just reading.
        let lessonFrame = NSScreen.main?.frame
        for screen in NSScreen.screens {
            let panel = dimPanel(frame: screen.frame)
            let hosting = NSHostingView(
                rootView: RehearsalView(
                    model: model,
                    showsChord: screen.frame == lessonFrame,
                    // Where a real thumbnail parks: just under the menu bar.
                    thumbnailTopInset: screen.frame.maxY - screen.visibleFrame.maxY
                ))
            // The panel is pinned to the screen frame, so the content must
            // never drive window sizing: with the default options, removing
            // the flight card invalidates intrinsic size and forces a
            // synchronous layout in the middle of the model writes - a
            // publish mid view-update, which wedges this panel's updates.
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            for panel in panels { panel.animator().alphaValue = 1 }
        }

        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { handleFlags($0) },
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
                handleFlags($0)
                return $0
            },
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { handleKeyDown($0) },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                handleKeyDown($0)
                return $0
            },
        ].compactMap { $0 }
    }

    static func dismiss() {
        dismiss(animated: true)
    }

    private static func dismiss(animated: Bool) {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        model = nil

        let dismissing = panels
        panels = []
        guard !dismissing.isEmpty else { return }

        guard animated else {
            for panel in dismissing { panel.close() }
            return
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = fadeDuration
                for panel in dismissing { panel.animator().alphaValue = 0 }
            },
            completionHandler: {
                // Animation completion handlers run on the main thread.
                MainActor.assumeIsolated { for panel in dismissing { panel.close() } }
            })
    }

    // MARK: - Events

    /// The same reading and the same detector as the real hotkey, so the demo
    /// accepts exactly the chords a real capture would.
    private static func handleFlags(_ event: NSEvent) {
        guard let model else { return }
        let chord = HotkeyMonitor.chordState(of: event)
        // flagsChanged fires for every modifier, Caps Lock and Fn included.
        // Writing these unconditionally would republish the model on keys the
        // rehearsal does not care about, re-rendering the drawn keycaps for
        // nothing - and those redraws share the frame that carries the flash.
        if model.leftDown != chord.left { model.leftDown = chord.left }
        if model.rightDown != chord.right { model.rightDown = chord.right }
        if model.shiftDown != chord.shift { model.shiftDown = chord.shift }
        // Only a phase that is asking for a chord feeds the detector, so a
        // press during the staged capture cannot arm anything.
        if model.phase.isLesson,
            detector.handle(
                leftKeyDown: chord.left, rightKeyDown: chord.right,
                otherModifiersDown: chord.others
            )
        {
            model.chordLanded(shiftHeld: chord.shift)
        }
    }

    private static func handleKeyDown(_ event: NSEvent) {
        guard let model else { return }
        switch model.phase {
        case .chordLesson:
            if event.keyCode == escapeKeyCode { model.onCancel() }
        case .shiftLesson:
            // The first capture already landed, so the Shift lesson is a
            // bonus rather than a gate: Esc finishes setup instead of
            // throwing away a rehearsal the user completed.
            if event.keyCode == escapeKeyCode { model.onComplete() }
        case .playingFull, .playingText:
            break
        case .done:
            model.onComplete()
        }
    }

    /// Like a capture-feedback overlay, but not mouse-transparent: a click on
    /// the dim is a cancel (or, after the chord, a finish), so the panel has to
    /// receive it. `.statusBar` keeps it above normal windows.
    private static func dimPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]
        return panel
    }
}

// MARK: - Model

/// The rehearsal's live state: which keys are physically down, which lesson is
/// running, and the staged capture choreography once a chord lands.
@MainActor
final class RehearsalModel: ObservableObject {
    /// One case per thing the screen shows, deliberately flat rather than a
    /// lesson with a payload: the view switches on this, and two states
    /// sharing a branch means sharing a view identity, which would leave the
    /// second lesson faded out and invisible when it arrives.
    enum Phase: Equatable {
        case chordLesson
        case playingFull
        case shiftLesson
        case playingText
        case done

        /// The Shift state this phase is asking for, or nil when it is not
        /// asking for a chord at all.
        var wantsShift: Bool? {
            switch self {
            case .chordLesson: false
            case .shiftLesson: true
            case .playingFull, .playingText, .done: nil
            }
        }

        var isLesson: Bool { wantsShift != nil }
    }

    @Published var leftDown = false
    @Published var rightDown = false
    @Published var shiftDown = false
    @Published private(set) var phase: Phase = .chordLesson
    @Published var flashOpacity: Double = 0
    /// The staged moment's one object, like the real `CaptureFeedback` panel:
    /// a card that exists, flies to its dock, reveals the shot, and fades.
    @Published var cardVisible = false
    @Published var cardDocked = false
    @Published var cardRevealed = false
    @Published var cardAlpha: Double = 0
    /// Bumped whenever a chord arrives with the wrong Shift state. The gate
    /// hint keys off it so a rejected attempt replays the hint instead of
    /// leaving the screen looking inert.
    @Published private(set) var rejections = 0

    let onCancel: @MainActor () -> Void
    let onComplete: @MainActor () -> Void

    /// True while the staged card stands for a text-only capture, so it
    /// surfaces the shape of text rather than a canned window.
    @Published var cardTextOnly = false

    init(
        onCancel: @escaping @MainActor () -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.onCancel = onCancel
        self.onComplete = onComplete
    }

    /// How long the landed capture holds before handing over to what comes
    /// next. Long enough to read the payoff line, which is the whole point
    /// of the beat.
    private static let payoffHold: TimeInterval = 3.0

    /// Guards the beat between the chord landing and the staged capture, so a
    /// release-and-repress inside that window cannot start a second one.
    private var capturePending = false

    /// A chord landed: the flash answers it on the very next frame. The
    /// keycaps sink live under the fingers, so no extra beat is needed for
    /// the press to be seen.
    ///
    /// Each lesson accepts only its own gesture. A chord with the wrong Shift
    /// state would teach the opposite of what the screen is asking for, so it
    /// nudges rather than playing - which is also what makes the dimmed
    /// Option caps in the second lesson honest.
    func chordLanded(shiftHeld: Bool) {
        guard let wantsShift = phase.wantsShift, !capturePending else { return }
        guard shiftHeld == wantsShift else {
            rejections += 1
            return
        }
        capturePending = true
        if wantsShift { stageTextCapture() } else { stageFullCapture() }
    }

    /// The capture moment, staged with the real choreography: the shutter, a
    /// wash marking the instant, then `CaptureFeedback`'s beats - a white
    /// card over the "window" (0.1s hold), a 0.4s ease-in flight to the
    /// thumbnail rect under the menu bar, the canned shot surfacing by
    /// crossfade (0.22s), a hold stretched for the lesson, a 0.3s fade -
    /// teaching the exact reflex a capture rewards, with nothing captured.
    private func stageFullCapture() {
        stageCapture(textOnly: false) { model in
            withAnimation(.easeInOut(duration: 0.3)) { model.phase = .shiftLesson }
        }
    }

    /// The text-only lesson plays the identical moment, because the real one
    /// does: same flash, same flight, same landing. Only the sound and what
    /// surfaces in the card differ, which is exactly the difference between
    /// the two captures.
    private func stageTextCapture() {
        stageCapture(textOnly: true) { model in
            withAnimation(.easeInOut(duration: 0.3)) { model.phase = .done }
        }
    }

    /// The capture moment, staged with the real choreography: the sound, a
    /// wash marking the instant, then `CaptureFeedback`'s exact beats - a
    /// card over the "window" (0.1s hold), a 0.4s ease-in flight to the
    /// thumbnail rect under the menu bar, the contents surfacing by crossfade
    /// (0.22s), a hold stretched for the lesson, a 0.3s fade - teaching the
    /// exact reflex a capture rewards, with nothing captured.
    private func stageCapture(
        textOnly: Bool, then finish: @escaping @MainActor (RehearsalModel) -> Void
    ) {
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = textOnly ? .playingText : .playingFull
        }
        cardTextOnly = textOnly
        // Deferred one runloop turn: audio spin-up on first play must never
        // hold back the frame that carries the flash.
        // The real moment's own sound, so the demo cannot teach a different
        // one from the capture it is rehearsing.
        DispatchQueue.main.async { CaptureFeedback.playCaptureSound() }

        // The wash marks the instant on every screen; the card is the moment
        // itself, on the lesson screen.
        flashOpacity = 1
        after(0.06) { model in
            withAnimation(.easeOut(duration: 0.35)) { model.flashOpacity = 0 }
        }

        cardVisible = true
        cardAlpha = 0.85
        after(0.1) { model in
            withAnimation(.easeIn(duration: 0.4)) { model.cardDocked = true }
        }
        after(0.5) { model in
            withAnimation(.easeOut(duration: 0.22)) {
                model.cardRevealed = true
                model.cardAlpha = 1
            }
        }
        after(0.5 + 0.22 + Self.payoffHold) { model in
            withAnimation(.easeIn(duration: 0.3)) { model.cardAlpha = 0 }
        }
        // Once the card is gone the screen is free for whatever comes next.
        after(0.5 + 0.22 + Self.payoffHold + 0.3) { model in
            model.cardDocked = false
            model.cardRevealed = false
            model.capturePending = false
            // The structural teardown goes last and the phase change gets its
            // own runloop turn: removing the card can trigger a synchronous
            // layout, and a phase publish landing inside that update would
            // wedge the lesson panel on the dark backdrop.
            model.cardVisible = false
            DispatchQueue.main.async { finish(model) }
        }
    }

    private func after(_ delay: TimeInterval, _ work: @escaping @MainActor (RehearsalModel) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // Scheduled on the main queue, so this runs on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                work(self)
            }
        }
    }

}

// MARK: - Views

/// One layer per screen. Every screen dims and takes the flash; the lesson
/// screen also gets the keycaps, the message, and the thumbnail.
private struct RehearsalView: View {
    @ObservedObject var model: RehearsalModel
    let showsChord: Bool
    let thumbnailTopInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            // Rehearsing keeps the desk visible behind the dim; the captured
            // moment deepens to near-void so the completion text never fights
            // a bright desktop showing through.
            Color.black.opacity(model.phase.isLesson ? 0.52 : 0.88)
                .contentShape(Rectangle())
                .onTapGesture {
                    switch model.phase {
                    case .chordLesson: model.onCancel()
                    case .shiftLesson, .done: model.onComplete()
                    case .playingFull, .playingText: break
                    }
                }

            if showsChord {
                lesson
            }

            // The flash covers every screen, the way a real capture moment
            // owns the whole desk for an instant: a hot core tinted with the
            // aura's pink toward the edges.
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.94, blue: 0.92), VoidTheme.auraPink],
                center: .center, startRadius: 0, endRadius: 1700
            )
            .opacity(model.flashOpacity)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
        .onAppear {
            guard showsChord, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    @ViewBuilder
    private var lesson: some View {
        switch model.phase {
        case .chordLesson:
            optionCaps(dimmed: false)
            chordPrompt

        case .shiftLesson:
            optionCaps(dimmed: !model.shiftDown)
            shiftPrompt

        case .playingFull:
            // The bridge into lesson two waits for the card to land and
            // reveal: while the white card crosses the centre it would sit
            // muddled behind it.
            payoff(
                title: "That is a full capture",
                detail: """
                    The screenshot plus every word in the window, including \
                    what was scrolled out of view.
                    """,
                visible: model.cardRevealed
            )

        case .playingText:
            payoff(
                title: "That is a text capture",
                detail: """
                    Everything in the window as markdown, even what was \
                    scrolled out of view. Skipping the screenshot saves \
                    tokens when you only need the words.
                    """,
                visible: model.cardRevealed
            )

        case .done:
            RadialGradient(
                colors: [VoidTheme.auraPink.opacity(0.4), .clear],
                center: .center, startRadius: 0, endRadius: 480
            )
            .allowsHitTesting(false)
            .transition(.opacity)

            VStack(spacing: 16) {
                Text("Setup complete")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(VoidTheme.ink)
                Text(
                    """
                    Both Option keys capture the window; add Shift for text \
                    only. Your next Claude Code message within two minutes \
                    carries it, in any session.
                    """
                )
                .font(.system(size: 21))
                .foregroundStyle(VoidTheme.muted)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 660)
                Text("Click anywhere or press any key to finish")
                    .font(VoidTheme.note)
                    .foregroundStyle(VoidTheme.faint)
                    .padding(.top, 10)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }

        if model.cardVisible {
            FlightCard(model: model, topInset: thumbnailTopInset)
        }
    }

    /// A fixed gap rather than edge-pinning: the caps flank the centre
    /// caption at the same distance on any screen, and they stay put across
    /// both lessons so only the centre changes. Dimmed means "pressing this
    /// does nothing yet", which is the Shift lesson's gate made visible.
    private func optionCaps(dimmed: Bool) -> some View {
        HStack(spacing: 760) {
            MechanicalKeycap(
                caption: "left", pressed: model.leftDown, pulsing: pulsing, dimmed: dimmed
            )
            MechanicalKeycap(
                caption: "right", pressed: model.rightDown, pulsing: pulsing, mirrored: true,
                dimmed: dimmed
            )
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var chordPrompt: some View {
        VStack(spacing: 12) {
            Text("Press left Option + right Option")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(VoidTheme.ink)
            Text("Captures the screenshot plus the window's full text")
                .font(VoidTheme.body)
                .foregroundStyle(VoidTheme.muted)
            Text("Esc to cancel")
                .font(VoidTheme.body)
                .foregroundStyle(VoidTheme.faint)
                .padding(.top, 6)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var shiftPrompt: some View {
        VStack(spacing: 14) {
            MechanicalKeycap(
                caption: "", pressed: model.shiftDown, pulsing: pulsing && !model.shiftDown,
                symbol: "shift", label: "shift"
            )
            Text("Great. Now hold Shift and press both Option keys")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(VoidTheme.ink)
            Text("Captures the text only, which costs fewer tokens")
                .font(VoidTheme.body)
                .foregroundStyle(VoidTheme.muted)
            // The gate, said out loud. Keyed on the rejection count so a
            // chord pressed without Shift replays the line instead of
            // leaving the screen looking like it ignored the keys.
            Text(model.shiftDown ? "Now press both Option keys" : "Hold Shift first")
                .font(VoidTheme.body)
                .foregroundStyle(model.shiftDown ? VoidTheme.muted : VoidTheme.faint)
                .id("\(model.shiftDown)-\(model.rejections)")
                .transition(.opacity)
            Text("Esc to finish")
                .font(VoidTheme.note)
                .foregroundStyle(VoidTheme.faint)
                .padding(.top, 6)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func payoff(title: String, detail: String, visible: Bool) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(VoidTheme.ink)
            Text(detail)
                .font(.system(size: 21))
                .foregroundStyle(VoidTheme.muted)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 660)
        }
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var accessibilitySummary: String {
        switch model.phase {
        case .chordLesson:
            return "Screen dimmed for the first-capture rehearsal. Press left Option and "
                + "right Option together to try the capture, or press Escape to cancel."
        case .shiftLesson:
            return "First capture done. Now hold Shift and press left Option and right "
                + "Option together to capture the window's text without a screenshot, "
                + "or press Escape to finish setup."
        case .playingFull:
            return "Playing the capture: the window flies to a thumbnail under the menu bar."
        case .playingText:
            return "Text captured, with no screenshot taken."
        case .done:
            return "Setup complete. Both Option keys capture the front window as a "
                + "screenshot and its full text as structured markdown; adding Shift "
                + "captures the text alone. Press any key to finish."
        }
    }
}

/// The staged moment's one object, mirroring the real `CaptureFeedback`
/// panel: a white card standing in for the captured window that flies to the
/// thumbnail rect under the menu bar, where the canned shot surfaces inside
/// it. The flight target IS the thumbnail rect - the same aspectFit the real
/// feedback uses - so there are no intermediate sizes.
private struct FlightCard: View {
    @ObservedObject var model: RehearsalModel
    let topInset: CGFloat

    // CaptureFeedback's own numbers.
    private static let thumbnailBox = CGSize(width: 260, height: 180)
    private static let arrivalTopMargin: CGFloat = 8
    private static let cornerRadius: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let window = demoWindowRect(in: geo.size)
            let fit = StillpaneCore.ScreenGeometry.aspectFit(window.size, in: Self.thumbnailBox)
            let docked = CGRect(
                x: (geo.size.width - fit.width) / 2,
                y: topInset + Self.arrivalTopMargin,
                width: fit.width,
                height: fit.height
            )
            let rect = model.cardDocked ? docked : window

            ZStack {
                Color.white
                Group {
                    if model.cardTextOnly {
                        CannedTextBody()
                    } else {
                        CannedWindowBody()
                    }
                }
                .opacity(model.cardRevealed ? 1 : 0)
            }
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                // The hairline a real card gains once the shot covers the
                // white fill.
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(model.cardRevealed ? 0.3 : 0), lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(model.cardRevealed ? 0.5 : 0), radius: 18, y: 6)
            .position(x: rect.midX, y: rect.midY)
            .opacity(model.cardAlpha)
        }
        .allowsHitTesting(false)
    }

    /// A plausible frontmost window for the card to stand in for: centered,
    /// 16:10, well clear of the screen edges.
    private func demoWindowRect(in size: CGSize) -> CGRect {
        let width = min(size.width * 0.52, 860)
        let height = width * 10 / 16
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

/// What surfaces in the landed card after a text-only capture: rows of soft
/// bars reading as a page of prose. It mirrors `CaptureFeedback.textCardImage`
/// so the rehearsal shows the same payoff a real text capture gives.
private struct CannedTextBody: View {
    private static let widths: [CGFloat] = [1.0, 0.82, 0.93, 0.66, 0.88, 0.74]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.widths.enumerated()), id: \.offset) { index, fraction in
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(index == 0 ? 0.34 : 0.17))
                        .frame(width: geo.size.width * fraction, height: 6)
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.1))
    }
}

/// The canned shot that surfaces in the landed card: a miniature window in
/// the same drawn vocabulary as the welcome animation. It teaches the reflex
/// without faking a screenshot.
private struct CannedWindowBody: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 7, height: 7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                line(maxWidth: .infinity, bright: true)
                line(maxWidth: 150)
                line(maxWidth: 190)
                line(maxWidth: 110)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(white: 0.1))
    }

    private func line(maxWidth: CGFloat, bright: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(bright ? 0.35 : 0.18))
            .frame(maxWidth: maxWidth)
            .frame(height: 6)
    }
}
