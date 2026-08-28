import AppKit
import SwiftUI

/// The app's one dialog: a void-themed modal used in place of NSAlert, so
/// no surface outside the setup assistant falls back to the system's light
/// panels. Same ground, type scale, and button language as the assistant.
///
/// Buttons follow NSAlert conventions: index 0 is the prominent default and
/// sits rightmost, the last button answers Escape.
@MainActor
enum VoidAlert {
    @discardableResult
    static func show(
        title: String, message: String, buttons: [String], monospacedMessage: Bool = false
    ) -> Int {
        present { respond in
            AlertView(
                title: title, message: message, buttons: buttons, mono: monospacedMessage,
                respond: respond
            )
        }
    }

    /// Runs any view as a void-themed modal. The view gets a `respond`
    /// closure; calling it ends the modal and returns that value.
    @discardableResult
    static func present<Content: View>(
        @ViewBuilder content: (@escaping (Int) -> Void) -> Content
    ) -> Int {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(VoidTheme.background)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        let view = content { index in
            NSApp.stopModal(withCode: NSApplication.ModalResponse(index))
        }
        let hosting = NSHostingController(rootView: view)
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        let response = NSApp.runModal(for: window)
        window.close()
        return response.rawValue
    }
}

private struct AlertView: View {
    let title: String
    let message: String
    let buttons: [String]
    let mono: Bool
    let respond: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(VoidTheme.ink)
            Text(message)
                .font(mono ? VoidTheme.mono : VoidTheme.note)
                .foregroundStyle(VoidTheme.muted)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                ForEach(Array(buttons.enumerated()).dropFirst().reversed(), id: \.offset) { index, label in
                    // Only a button that means "back out" answers Escape;
                    // NSAlert's convention, kept.
                    let button = Button(label) { respond(index) }
                        .buttonStyle(.voidQuiet)
                        .fixedSize()
                    if label == "Cancel" || label == "Not Now" {
                        button.keyboardShortcut(.cancelAction)
                    } else {
                        button
                    }
                }
                Button(buttons[0]) { respond(0) }
                    .buttonStyle(.voidProminent)
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
            }
            .padding(.top, 8)
        }
        .padding(28)
        // Grows past the base width rather than ever wrapping a button label.
        .frame(minWidth: 480, alignment: .leading)
        .background(VoidTheme.background)
    }
}
