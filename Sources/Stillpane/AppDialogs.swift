import StillpaneCore
import SwiftUI

/// The designed modal behind the menu bar's destructive action. It runs
/// through `VoidAlert.present` and follows the destructive-modal pattern the
/// void theme adapts: an icon manifest of what goes, and a red action.

struct UninstallConfirmView: View {
    let respond: (Int) -> Void

    private let removals: [(symbol: String, text: String)] = [
        ("puzzlepiece.extension", "The Claude Code plugin and its marketplace entry"),
        ("folder", "Your captures folder (~/.claude/stillpane)"),
        ("power", "The Launch at Login registration"),
        ("gearshape", "stillpane's settings and permission grants"),
        ("trash", "The app itself, moved to the Trash"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Uninstall stillpane?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(VoidTheme.ink)
            Text("This removes everything stillpane set up.")
                .font(VoidTheme.note)
                .foregroundStyle(VoidTheme.muted)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(removals.enumerated()), id: \.offset) { index, removal in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                    HStack(spacing: 12) {
                        Image(systemName: removal.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(VoidTheme.muted)
                            .frame(width: 22)
                        Text(removal.text)
                            .font(VoidTheme.note)
                            .foregroundStyle(VoidTheme.ink.opacity(0.85))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )

            HStack(spacing: 10) {
                Spacer()
                // Return deliberately does nothing here: a destructive
                // default is how uninstalls happen by accident.
                Button("Cancel") { respond(1) }
                    .buttonStyle(.voidQuiet)
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
                Button("Uninstall") { respond(0) }
                    .buttonStyle(.voidDestructive)
                    .fixedSize()
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 520, alignment: .leading)
        .background(VoidTheme.background)
    }
}
