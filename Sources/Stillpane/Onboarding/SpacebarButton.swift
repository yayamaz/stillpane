import AppKit
import SwiftUI

/// The setup flow's primary control: a spacebar keycap drawn in the
/// rehearsal's frustum language. Clicking presses it, and holding physical
/// Space sinks the cap live with the action firing on release - advancing
/// setup is itself a keypress on a drawn key, which is the reflex the whole
/// flow teaches. The Space monitor only acts while the hosting window is key
/// and the button is enabled, which keeps VoidAlert dialogs, the rehearsal
/// overlay (the setup window hides behind it), and gated steps Space-dead.
struct SpacebarButton: View {
    let title: String
    var isEnabled = true
    /// The welcome screen teaches the pattern once; later steps let the
    /// shape speak.
    var showsSpaceHint = false
    let action: () -> Void

    @State private var spaceDown = false
    @State private var monitor: Any?
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) { Text(title) }
                .buttonStyle(SpacebarStyle(title: title, spaceDown: spaceDown))
                .keyboardShortcut(.defaultAction)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.45)
                .pointingHandOnHover(isActive: isEnabled)
                .accessibilityLabel(title)

            if showsSpaceHint {
                Text("Click, or press Space")
                    .font(.system(size: 15))
                    .foregroundStyle(VoidTheme.faint)
            }
        }
        .background(WindowReader { hostWindow = $0 })
        .onAppear(perform: installMonitor)
        .onDisappear(perform: removeMonitor)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { spaceDown = false }
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            handle(event)
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        spaceDown = false
    }

    /// Space (keyCode 49), unmodified, while our window is key: key-down
    /// sinks the cap, key-up fires - standard button semantics, so a held
    /// press can still be abandoned by clicking elsewhere first. Everything
    /// else passes through untouched.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 49,
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
            let window = hostWindow, window.isKeyWindow, isEnabled
        else { return event }
        switch event.type {
        case .keyDown:
            if !event.isARepeat { spaceDown = true }
            return nil
        case .keyUp:
            guard spaceDown else { return event }
            spaceDown = false
            action()
            return nil
        default:
            return event
        }
    }
}

/// Draws the cap. `configuration.isPressed` carries pointer presses; the
/// physical Space state arrives from outside, and either one sinks the cap.
private struct SpacebarStyle: ButtonStyle {
    let title: String
    let spaceDown: Bool

    nonisolated static let geometry = KeycapGeometry(
        faceSize: CGSize(width: 240, height: 46),
        cornerRadius: 12,
        shear: -0.14,
        depth: 18,
        flare: 1.09,
        faceInset: CGSize(width: 0.92, height: 0.88)
    )
    private static let travel: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || spaceDown
        return ZStack(alignment: .bottom) {
            // Ground shadow: tightens and darkens as the cap sinks.
            Ellipse()
                .fill(Color.black.opacity(pressed ? 0.65 : 0.45))
                .frame(width: pressed ? 268 : 292, height: 12)
                .blur(radius: 8)

            SpacebarCap(title: title, pressed: pressed)
                .padding(.bottom, 4)
                .offset(y: pressed ? Self.travel : 0)
        }
        .frame(width: 310, height: 92)
        .shadow(
            color: .white.opacity(pressed ? 0.4 : 0.1),
            radius: pressed ? 20 : 11
        )
        .animation(.spring(response: 0.16, dampingFraction: 0.75), value: pressed)
        .contentShape(Rectangle())
    }
}

private struct SpacebarCap: View {
    let title: String
    let pressed: Bool

    /// Built once, like the rehearsal caps: the press redraw only fills and
    /// strokes, so sinking the cap never costs a path-boolean rebuild.
    private nonisolated static let prebuilt = SpacebarStyle.geometry.paths(
        in: CGSize(width: 300, height: 82))

    var body: some View {
        Canvas { context, size in
            let (solid, face) = Self.prebuilt
            let fb = face.boundingRect
            let solidBounds = solid.boundingRect

            let outline = GraphicsContext.Shading.color(VoidTheme.ink)
            context.fill(
                solid,
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.16), Color(white: 0.02)]),
                    startPoint: CGPoint(x: fb.midX, y: fb.maxY - 8),
                    endPoint: CGPoint(x: fb.midX, y: solidBounds.maxY)
                ))
            context.stroke(solid, with: outline, lineWidth: 3)

            context.fill(
                face,
                with: .linearGradient(
                    Gradient(
                        colors: pressed
                            ? [Color(white: 0.26), Color(white: 0.15)]
                            : [Color(white: 0.34), Color(white: 0.2)]),
                    startPoint: CGPoint(x: fb.midX, y: fb.minY),
                    endPoint: CGPoint(x: fb.midX, y: fb.maxY)
                ))
            context.stroke(face, with: outline, lineWidth: 3)

            // Legend at half the face's shear, same as the Option caps.
            var legend = context
            legend.translateBy(x: fb.midX, y: fb.midY)
            legend.concatenate(
                CGAffineTransform(
                    a: 1, b: 0, c: SpacebarStyle.geometry.shear / 2, d: 1, tx: 0, ty: 0))
            legend.draw(
                context.resolve(
                    Text(title)
                        .font(VoidTheme.button)
                        .foregroundStyle(VoidTheme.ink)
                ),
                at: .zero
            )
        }
        .frame(width: 300, height: 82)
    }
}

/// Hands the hosting NSWindow to SwiftUI so the Space monitor can check
/// key-window status at event time.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onWindow(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in onWindow(nsView?.window) }
    }
}
