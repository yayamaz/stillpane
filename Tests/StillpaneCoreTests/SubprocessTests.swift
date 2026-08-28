import Foundation
import XCTest

@testable import StillpaneCore

final class SubprocessTests: XCTestCase {
    private func sleeper(_ seconds: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        return process
    }

    func testProcessExitingWithinTimeoutReturnsTrue() throws {
        let process = sleeper("0")
        try process.run()
        XCTAssertTrue(Subprocess.waitOrKill(process, timeout: 5))
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testTimedOutProcessIsKilledAndReaped() throws {
        let process = sleeper("100")
        try process.run()
        let start = Date()
        XCTAssertFalse(Subprocess.waitOrKill(process, timeout: 0.2))
        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testSigtermImmuneProcessIsStillKilled() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "trap '' TERM; sleep 100"]
        try process.run()
        XCTAssertFalse(Subprocess.waitOrKill(process, timeout: 0.5))
        XCTAssertFalse(process.isRunning)
    }
}
