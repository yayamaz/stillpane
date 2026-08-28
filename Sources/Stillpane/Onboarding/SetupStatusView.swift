import StillpaneCore
import SwiftUI

/// The setup status board: what a finished install shows when it is reopened
/// by hand. Every link in the chain, its state in words, and a traffic-light
/// dot - the sanctioned second use of colour.
///
/// A row that names a step is a button into that step, so the repair lives
/// where it was always built rather than being rebuilt here. Rows nothing can
/// be done about from the assistant - the fate of the latest capture - stay
/// plain text.
struct SetupStatusView: View {
    @ObservedObject var state: OnboardingState

    private var worst: SetupItem.Health {
        if state.statusItems.contains(where: { $0.health == .fail }) { return .fail }
        if state.statusItems.contains(where: { $0.health == .warn }) { return .warn }
        return .ok
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            rows
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Self.color(worst).opacity(0.16)).frame(width: 44, height: 44)
                Image(systemName: worst == .ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Self.color(worst))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(VoidTheme.ink)
                Text("stillpane \(StillpaneVersion.version) - macOS \(Self.osVersion)")
                    .font(VoidTheme.note)
                    .foregroundStyle(VoidTheme.faint)
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(state.statusItems.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
                if let step = item.step {
                    Button {
                        state.openStep(step)
                    } label: {
                        StatusRow(item: item, opens: true)
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                } else {
                    StatusRow(item: item, opens: false)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var footer: some View {
        VStack(spacing: 14) {
            SpacebarButton(title: "Close") { OnboardingWindow.close() }
            QuietLink("Run the walkthrough again") { state.replayWalkthrough() }
        }
        .frame(maxWidth: .infinity)
    }

    private var verdict: String {
        switch worst {
        case .fail: "Setup needs attention"
        case .warn: "Working, with notes"
        default: "Everything is working"
        }
    }

    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static func color(_ health: SetupItem.Health) -> Color {
        switch health {
        case .ok: VoidTheme.healthGreen
        case .warn: VoidTheme.healthAmber
        case .fail: VoidTheme.healthRed
        case .info: VoidTheme.faint
        }
    }
}

/// One line of the board. The chevron is the only thing that marks a row as
/// openable, which is enough on a list where most rows are.
private struct StatusRow: View {
    let item: SetupItem
    let opens: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(SetupStatusView.color(item.health))
                .frame(width: 9, height: 9)
                .offset(y: -1)
            Text(item.name)
                .font(VoidTheme.note)
                .foregroundStyle(VoidTheme.ink)
            Spacer(minLength: 24)
            Text(item.detail)
                .font(VoidTheme.note)
                .foregroundStyle(VoidTheme.muted)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VoidTheme.faint)
                .opacity(opens ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
