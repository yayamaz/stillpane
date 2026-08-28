import SwiftUI

// The drawn keycap, shared by the first-capture rehearsal. It is drawn rather
// than shipped as an image because the cap is a state machine, not a picture:
// pressing it changes the face gradient, sinks the solid toward its shadow,
// and swaps the glow. One `KeycapGeometry` also serves the left cap, the
// mirrored right cap, the Shift cap, and - stretched wide - every
// `SpacebarButton` primary, which is what makes them read as keys from the
// same keyboard.

/// A keycap in the iconic three-quarter view keyboard-key illustrations use:
/// the top face a sheared parallelogram, the body extruded straight down from
/// it, and a bold light outline around both the silhouette and the face -
/// blueprint style, filled with the void's grays. Holding the matching
/// physical key sinks the whole cap toward its ground shadow.
struct MechanicalKeycap: View {
    let caption: String
    let pressed: Bool
    let pulsing: Bool
    var mirrored = false
    /// Dimmed means "pressing this does nothing yet": the Shift lesson holds
    /// the Option caps back until Shift is actually down.
    var dimmed = false
    var symbol = "option"
    var label = "option"

    private static let travel: CGFloat = 7

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                // Ground shadow: tightens and darkens as the cap sinks.
                Ellipse()
                    .fill(Color.black.opacity(pressed ? 0.65 : 0.45))
                    .frame(width: pressed ? 130 : 146, height: 16)
                    .blur(radius: 9)

                IsoKeycap(pressed: pressed, mirrored: mirrored, symbol: symbol, label: label)
                    .padding(.bottom, 6)
                    .offset(y: pressed ? Self.travel : 0)
            }
            .frame(width: 195, height: 168)
            .shadow(
                color: .white.opacity(pressed ? 0.45 : pulsing ? 0.32 : 0.1),
                radius: pressed ? 26 : pulsing ? 24 : 13
            )
            .animation(.spring(response: 0.16, dampingFraction: 0.75), value: pressed)

            if !caption.isEmpty {
                Text(caption)
                    .font(VoidTheme.body)
                    .foregroundStyle(VoidTheme.muted)
            }
        }
        // No `.animation` here on purpose: this subtree contains the drawn
        // Canvas whose redraw shares the frame that carries the capture
        // flash, and an animated modifier around it is exactly the kind of
        // per-frame work that would put a visible delay between the keypress
        // and the flash. The dim reads fine as a hard cut.
        .opacity(dimmed ? 0.3 : 1)
    }
}

/// The drawing itself: a keycap frustum in the iconic three-quarter view. The
/// solid is the union of the sheared top face interpolated outward and
/// downward into a wider base, which produces the flared side walls and, when
/// stroked, the silhouette's slanted edges.
private struct IsoKeycap: View {
    let pressed: Bool
    var mirrored = false
    /// The legend on the face. The solid is identical for every cap, so a
    /// Shift key is this same drawing wearing a different glyph and word -
    /// which is what keeps all three reading as one keyboard.
    var symbol = "option"
    var label = "option"

    /// The shared solid at Option-cap proportions; the setup flow's spacebar
    /// is the same geometry stretched wide (`SpacebarButton`).
    private nonisolated static let geometry = KeycapGeometry(
        faceSize: CGSize(width: 112, height: 84),
        cornerRadius: 14,
        shear: -0.22,
        depth: 30,
        flare: 1.16,
        faceInset: CGSize(width: 0.88, height: 0.88)
    )
    private static let outlineWidth: CGFloat = 3
    private nonisolated static let canvasSize = CGSize(width: 185, height: 150)
    /// The cap redraws on every key-state change - the same frame that must
    /// carry the capture flash - and the solid costs 24 path unions to build.
    /// Built once here (thread-safe lazy static init; Path is immutable after
    /// construction), so redraws only fill and stroke.
    private nonisolated static let prebuilt = (
        plain: geometry.paths(in: canvasSize, mirrored: false),
        mirrored: geometry.paths(in: canvasSize, mirrored: true)
    )

    var body: some View {
        Canvas { context, size in
            let lean = mirrored ? -Self.geometry.shear : Self.geometry.shear
            let (solid, face) = mirrored ? Self.prebuilt.mirrored : Self.prebuilt.plain
            let fb = face.boundingRect
            let solidBounds = solid.boundingRect

            let outline = GraphicsContext.Shading.color(VoidTheme.ink)
            context.fill(
                solid,
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.16), Color(white: 0.02)]),
                    startPoint: CGPoint(x: fb.midX, y: fb.maxY - 10),
                    endPoint: CGPoint(x: fb.midX, y: solidBounds.maxY)
                ))
            context.stroke(solid, with: outline, lineWidth: Self.outlineWidth)

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
            context.stroke(face, with: outline, lineWidth: Self.outlineWidth)

            // Legend at half the face's shear: aligned enough to sit on it,
            // upright enough that the glyph does not look broken.
            var legend = context
            legend.translateBy(x: fb.midX, y: fb.midY)
            legend.concatenate(CGAffineTransform(a: 1, b: 0, c: lean / 2, d: 1, tx: 0, ty: 0))
            legend.draw(
                context.resolve(
                    Text(Image(systemName: symbol))
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(VoidTheme.ink)
                ),
                at: CGPoint(x: 0, y: -8)
            )
            legend.draw(
                context.resolve(
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VoidTheme.ink.opacity(0.6))
                ),
                at: CGPoint(x: 0, y: 20)
            )
        }
        .frame(width: 185, height: 150)
    }
}
