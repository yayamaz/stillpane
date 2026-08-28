import SwiftUI

/// The promise, drawn: the chord lights up, the window flashes the way a real
/// capture flashes it, and it arrives in Claude Code. Shapes and SF Symbols
/// only, no bitmap assets, on a slow loop that reads as an explanation rather
/// than as decoration.
struct WelcomeVisual: View {
    private enum Beat: Int, CaseIterable {
        case chord, window, claude
    }

    private static let interval: TimeInterval = 1.1
    private let tick = Timer.publish(every: interval, on: .main, in: .common).autoconnect()

    @State private var beat = Beat.chord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KeyCap(caption: "left", active: beat == .chord)
            KeyCap(caption: "right", active: beat == .chord)
            Connector(active: beat != .chord)
            WindowGlyph(active: beat == .window)
            Connector(active: beat == .claude)
            ClaudeGlyph(active: beat == .claude)
        }
        .onReceive(tick) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                beat = Beat(rawValue: (beat.rawValue + 1) % Beat.allCases.count) ?? .chord
            }
        }
        // One description for the whole sequence; six animated shapes announced
        // one at a time would be noise.
        .accessibilityElement()
        .accessibilityLabel(
            "Pressing both Option keys sends the window in front of you to Claude Code."
        )
    }
}

/// Height every glyph is centered in, so the captions below them line up.
private let glyphHeight: CGFloat = 70

private struct KeyCap: View {
    let caption: String
    let active: Bool

    var body: some View {
        GlyphColumn(caption: caption) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? VoidTheme.ink : Color.primary.opacity(0.07))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "option")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(active ? Color.black : Color.secondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1))
                )
                .scaleEffect(active ? 1.06 : 1)
                .shadow(color: Color.white.opacity(active ? 0.3 : 0), radius: 7, y: 2)
        }
    }
}

private struct WindowGlyph: View {
    let active: Bool

    var body: some View {
        GlyphColumn(caption: "your window") {
            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.secondary.opacity(0.45)).frame(width: 4, height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 13)
                .background(Color.primary.opacity(0.06))

                VStack(alignment: .leading, spacing: 4) {
                    line(width: .infinity)
                    line(width: 34)
                    line(width: 46)
                }
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 86, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            // The white wash is the capture flash, in miniature.
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white)
                    .opacity(active ? 0.55 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        active ? VoidTheme.ink : Color.primary.opacity(0.12),
                        lineWidth: active ? 2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(active ? 1.05 : 1)
        }
    }

    private func line(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.secondary.opacity(0.3))
            .frame(maxWidth: width)
            .frame(height: 4)
    }
}

private struct ClaudeGlyph: View {
    let active: Bool

    var body: some View {
        GlyphColumn(caption: "Claude Code") {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(active ? VoidTheme.ink : Color.secondary)
                .frame(width: 54, height: 54)
                .background(
                    Circle().fill(
                        active ? Color.white.opacity(0.14) : Color.primary.opacity(0.06)
                    )
                )
                .scaleEffect(active ? 1.08 : 1)
        }
    }
}

private struct Connector: View {
    let active: Bool

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(active ? VoidTheme.ink : Color.secondary.opacity(0.4))
            .frame(height: glyphHeight)
    }
}

/// A glyph centered in a fixed-height box with its caption underneath, so a row
/// of differently sized glyphs still has one caption baseline.
private struct GlyphColumn<Glyph: View>: View {
    let caption: String
    @ViewBuilder var glyph: Glyph

    var body: some View {
        VStack(spacing: 7) {
            glyph.frame(height: glyphHeight)
            Text(caption)
                .font(VoidTheme.note)
                .foregroundStyle(.secondary)
        }
    }
}
