import XCTest

@testable import StillpaneCore

final class CaptureModeTests: XCTestCase {
    func testPlainChordFollowsTheDefault() {
        XCTAssertEqual(
            CaptureMode.resolve(defaultTextOnly: false, shiftHeld: false), .screenshotAndText)
        XCTAssertEqual(CaptureMode.resolve(defaultTextOnly: true, shiftHeld: false), .textOnly)
    }

    /// Shift inverts, so it stays useful for a user who set text-only as the
    /// default and wants a picture just this once.
    func testShiftInvertsTheDefaultBothWays() {
        XCTAssertEqual(CaptureMode.resolve(defaultTextOnly: false, shiftHeld: true), .textOnly)
        XCTAssertEqual(
            CaptureMode.resolve(defaultTextOnly: true, shiftHeld: true), .screenshotAndText)
    }

    func testOnlyTheFullModeWantsAScreenshot() {
        XCTAssertTrue(CaptureMode.screenshotAndText.wantsScreenshot)
        XCTAssertFalse(CaptureMode.textOnly.wantsScreenshot)
    }
}
