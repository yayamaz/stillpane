import XCTest

@testable import StillpaneCore

final class SmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(StillpaneVersion.version.isEmpty)
    }
}
