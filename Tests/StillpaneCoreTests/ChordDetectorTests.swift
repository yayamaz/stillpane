import XCTest

@testable import StillpaneCore

final class ChordDetectorTests: XCTestCase {
    func testFiresWhenBothKeysHeld() {
        var detector = ChordDetector()
        XCTAssertFalse(detector.handle(leftKeyDown: true, rightKeyDown: false, otherModifiersDown: false))
        XCTAssertTrue(detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false))
    }

    func testDoesNotRefireWhileHeld() {
        var detector = ChordDetector()
        _ = detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false)
        XCTAssertFalse(detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false))
    }

    func testRearmsOnlyAfterFullRelease() {
        var detector = ChordDetector()
        _ = detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false)
        XCTAssertFalse(detector.handle(leftKeyDown: true, rightKeyDown: false, otherModifiersDown: false))
        XCTAssertFalse(detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false))
        _ = detector.handle(leftKeyDown: false, rightKeyDown: false, otherModifiersDown: false)
        XCTAssertTrue(detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false))
    }

    func testOtherModifiersSuppressFiring() {
        var detector = ChordDetector()
        XCTAssertFalse(detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: true))
        // Still no fire until everything is released first.
        XCTAssertFalse(detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false))
        _ = detector.handle(leftKeyDown: false, rightKeyDown: false, otherModifiersDown: false)
        XCTAssertTrue(detector.handle(leftKeyDown: true, rightKeyDown: true, otherModifiersDown: false))
    }
}
