import SwiftUI

/// The setup assistant's visual identity - a focused void: pitch-black window,
/// monochrome ink, and no colour anywhere except the aurora that greets a
/// finished setup. The window is pinned to dark appearance, so system-drawn
/// controls follow along without restyling.
enum VoidTheme {
    /// Near-black rather than pure black, so the window still separates from a
    /// dark wallpaper behind it.
    static let background = Color(red: 0.04, green: 0.04, blue: 0.045)
    static let ink = Color(red: 0.96, green: 0.96, blue: 0.955)
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)

    /// The one tone of colour in the flow: the capture flash, the rehearsal's
    /// completion aura, and the finished window's glow all share it.
    static let auraPink = Color(red: 1.0, green: 0.44, blue: 0.42)
    static let auraViolet = Color(red: 0.49, green: 0.36, blue: 1.0)

    /// Health semantics: setup status reads in traffic-light colour, the one
    /// other place colour is allowed. Hues match the macOS window controls so
    /// they feel native on the void.
    static let healthGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let healthAmber = Color(red: 1.0, green: 0.70, blue: 0.25)
    static let healthRed = Color(red: 1.0, green: 0.37, blue: 0.34)
    /// Destructive action fill - deeper than healthRed so white text carries.
    static let destructive = Color(red: 0.90, green: 0.28, blue: 0.30)

    // MARK: - Type scale
    // Defined once, read everywhere. Every piece of reading text on every
    // surface uses one of these; only display type inside drawn art (keycap
    // legends, the welcome visual's glyphs, step titles) sizes itself locally.
    static let body = Font.system(size: 19)
    static let note = Font.system(size: 17)
    static let noteStrong = Font.system(size: 17, weight: .semibold)
    static let mono = Font.system(size: 16, design: .monospaced)
    static let button = Font.system(size: 18, weight: .semibold)
    static let buttonQuiet = Font.system(size: 18, weight: .medium)
}

/// The pointing hand every clickable control wears on hover - buttons and
/// quiet links alike, so nothing interactive reads as inert text or artwork.
/// Tracking the push locally keeps the cursor stack balanced even if hover
/// state and enablement change out from under each other.
struct PointingHandOnHover: ViewModifier {
    var isActive = true
    @State private var pushed = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside, isActive, !pushed {
                NSCursor.pointingHand.push()
                pushed = true
            } else if !inside, pushed {
                NSCursor.pop()
                pushed = false
            }
        }
    }
}

extension View {
    func pointingHandOnHover(isActive: Bool = true) -> some View {
        modifier(PointingHandOnHover(isActive: isActive))
    }
}

/// A destructive primary: same shape as the prominent button, red fill,
/// white label. Reserved for actions that remove things.
struct VoidDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VoidTheme.button)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VoidTheme.destructive)
            )
            .opacity(configuration.isPressed ? 0.75 : isEnabled ? 1 : 0.4)
            .pointingHandOnHover(isActive: isEnabled)
    }
}

extension ButtonStyle where Self == VoidDestructiveButtonStyle {
    static var voidDestructive: VoidDestructiveButtonStyle { VoidDestructiveButtonStyle() }
}

/// The one loud control on any step: ink fill, black label. Everything else on
/// the screen defers to it, which is what keeps each step to a single obvious
/// action.
struct VoidProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VoidTheme.button)
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VoidTheme.ink)
            )
            .opacity(configuration.isPressed ? 0.75 : isEnabled ? 1 : 0.4)
            .pointingHandOnHover(isActive: isEnabled)
    }
}

/// A supporting action, one shade above the background.
struct VoidQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VoidTheme.buttonQuiet)
            .foregroundStyle(VoidTheme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .pointingHandOnHover()
    }
}

extension ButtonStyle where Self == VoidProminentButtonStyle {
    static var voidProminent: VoidProminentButtonStyle { .init() }
}

extension ButtonStyle where Self == VoidQuietButtonStyle {
    static var voidQuiet: VoidQuietButtonStyle { .init() }
}
