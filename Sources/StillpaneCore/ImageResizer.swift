import CoreGraphics

/// Downscales screenshots to the width beyond which Claude's vision
/// gains nothing, saving image tokens with no loss of understanding.
public enum ImageResizer {
    public static let claudeMaxWidth = 1500

    public static func downscaled(_ image: CGImage, maxWidth: Int) -> CGImage {
        guard image.width > maxWidth else { return image }
        let scale = Double(maxWidth) / Double(image.width)
        let height = Int((Double(image.height) * scale).rounded())
        guard
            let context = CGContext(
                data: nil, width: maxWidth, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage() ?? image
    }
}
