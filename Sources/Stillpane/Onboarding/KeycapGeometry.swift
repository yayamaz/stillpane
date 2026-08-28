import SwiftUI

/// The shared keycap solid: a rounded face sheared into three-quarter view,
/// extruded down into a flared base by unioning interpolated slices. The
/// rehearsal's Option caps and the setup flow's spacebar button are this one
/// drawing at different proportions, which is what keeps them reading as keys
/// from the same keyboard.
struct KeycapGeometry: Sendable {
    var faceSize: CGSize
    var cornerRadius: CGFloat
    var shear: CGFloat
    var depth: CGFloat
    var flare: CGFloat
    /// Scale factors that shrink the top slice into the face, leaving the rim
    /// of base visible around it - a thin edge above, a thick wall below, the
    /// way a real cap reads.
    var faceInset: CGSize
    /// How far the inset face drops toward the base.
    var faceDrop: CGFloat = 2

    /// The finished solid and its face, centered in `size`.
    func paths(in size: CGSize, mirrored: Bool = false) -> (solid: Path, face: Path) {
        let lean = mirrored ? -shear : shear
        let shearT = CGAffineTransform(a: 1, b: 0, c: lean, d: 1, tx: 0, ty: 0)
        let raw = Path(
            roundedRect: CGRect(origin: .zero, size: faceSize),
            cornerRadius: cornerRadius,
            style: .continuous
        ).applying(shearT)
        let rb = raw.boundingRect

        func slice(_ t: CGFloat) -> Path {
            let s = 1 + (flare - 1) * t
            return raw.applying(
                CGAffineTransform(translationX: rb.midX, y: rb.midY)
                    .scaledBy(x: s, y: s)
                    .translatedBy(x: -rb.midX, y: -rb.midY)
                    .concatenating(.init(translationX: 0, y: depth * t))
            )
        }
        var solid = slice(0)
        for i in 1...24 { solid = solid.union(slice(CGFloat(i) / 24)) }

        let sb = solid.boundingRect
        let place = CGAffineTransform(
            translationX: (size.width - sb.width) / 2 - sb.minX,
            y: (size.height - sb.height) / 2 - sb.minY
        )
        solid = solid.applying(place)

        let faceSlice = slice(0)
        let f0 = faceSlice.boundingRect
        let face = faceSlice.applying(
            CGAffineTransform(translationX: f0.midX, y: f0.midY)
                .scaledBy(x: faceInset.width, y: faceInset.height)
                .translatedBy(x: -f0.midX, y: -f0.midY)
        ).applying(place).applying(.init(translationX: 0, y: faceDrop))
        return (solid, face)
    }
}
