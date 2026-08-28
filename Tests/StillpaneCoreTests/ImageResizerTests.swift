import CoreGraphics
import XCTest

@testable import StillpaneCore

final class ImageResizerTests: XCTestCase {
    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    func testWideImageIsDownscaledPreservingAspect() {
        let result = ImageResizer.downscaled(makeImage(width: 3000, height: 2000), maxWidth: 1500)
        XCTAssertEqual(result.width, 1500)
        XCTAssertEqual(result.height, 1000)
    }

    func testNarrowImageIsUntouched() {
        let image = makeImage(width: 800, height: 600)
        let result = ImageResizer.downscaled(image, maxWidth: 1500)
        XCTAssertEqual(result.width, 800)
        XCTAssertEqual(result.height, 600)
    }
}
