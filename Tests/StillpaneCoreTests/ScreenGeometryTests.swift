import CoreGraphics
import XCTest

@testable import StillpaneCore

final class ScreenGeometryTests: XCTestCase {
    // A 1080-tall primary display: CG y=0 is its top edge, AppKit y=1080 is.
    private let primaryMaxY: CGFloat = 1080

    func testFlippingAWindowOnThePrimaryDisplay() {
        let cg = CGRect(x: 100, y: 200, width: 800, height: 600)
        XCTAssertEqual(
            ScreenGeometry.flipped(cg, primaryMaxY: primaryMaxY),
            CGRect(x: 100, y: 280, width: 800, height: 600)
        )
    }

    func testFlippingIsItsOwnInverse() {
        let cg = CGRect(x: 12, y: 34, width: 56, height: 78)
        let there = ScreenGeometry.flipped(cg, primaryMaxY: primaryMaxY)
        XCTAssertEqual(ScreenGeometry.flipped(there, primaryMaxY: primaryMaxY), cg)
    }

    func testWindowFlushWithTheTopOfThePrimaryDisplay() {
        let cg = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(
            ScreenGeometry.flipped(cg, primaryMaxY: primaryMaxY),
            CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
    }

    // A display sitting above the primary one has negative y in both spaces.
    func testFlippingAWindowOnADisplayAboveThePrimary() {
        let cg = CGRect(x: 0, y: -900, width: 1440, height: 900)
        XCTAssertEqual(
            ScreenGeometry.flipped(cg, primaryMaxY: primaryMaxY),
            CGRect(x: 0, y: 1080, width: 1440, height: 900)
        )
    }

    func testAspectFitShrinksAWideImageToTheBoxWidth() {
        let fitted = ScreenGeometry.aspectFit(
            CGSize(width: 1280, height: 800), in: CGSize(width: 280, height: 200)
        )
        XCTAssertEqual(fitted, CGSize(width: 280, height: 175))
    }

    func testAspectFitShrinksATallImageToTheBoxHeight() {
        let fitted = ScreenGeometry.aspectFit(
            CGSize(width: 800, height: 1600), in: CGSize(width: 280, height: 200)
        )
        XCTAssertEqual(fitted, CGSize(width: 100, height: 200))
    }

    func testAspectFitNeverScalesUp() {
        let small = CGSize(width: 120, height: 90)
        XCTAssertEqual(
            ScreenGeometry.aspectFit(small, in: CGSize(width: 280, height: 200)), small
        )
    }

    func testAspectFitRejectsDegenerateSizes() {
        XCTAssertEqual(
            ScreenGeometry.aspectFit(.zero, in: CGSize(width: 280, height: 200)), .zero
        )
        XCTAssertEqual(
            ScreenGeometry.aspectFit(CGSize(width: 100, height: 100), in: .zero), .zero
        )
    }
}
