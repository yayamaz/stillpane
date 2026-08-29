import XCTest

@testable import StillpaneCore

final class UpdateScheduleTests: XCTestCase {
    /// Fixed zone: the rule is "a calendar day", and a floating one would make
    /// the boundary cases depend on where the test runs.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    func testDueWhenNothingRecorded() {
        XCTAssertTrue(UpdateSchedule.isDue(last: nil, now: date("2026-08-29T09:00:00Z"), calendar: calendar))
    }

    func testNotDueTwiceInOneDay() {
        XCTAssertFalse(
            UpdateSchedule.isDue(
                last: date("2026-08-29T00:01:00Z"),
                now: date("2026-08-29T23:59:00Z"),
                calendar: calendar))
    }

    func testDueOnTheNextDayEvenMinutesLater() {
        XCTAssertTrue(
            UpdateSchedule.isDue(
                last: date("2026-08-29T23:59:00Z"),
                now: date("2026-08-30T00:01:00Z"),
                calendar: calendar))
    }

    func testNotDueAfterAlmostAFullDayWithinTheSameDay() {
        XCTAssertFalse(
            UpdateSchedule.isDue(
                last: date("2026-08-29T00:30:00Z"),
                now: date("2026-08-29T22:30:00Z"),
                calendar: calendar))
    }

    func testStampInTheFutureDoesNotFreezeTheCheck() {
        XCTAssertTrue(
            UpdateSchedule.isDue(
                last: date("2027-01-01T00:00:00Z"),
                now: date("2026-08-29T09:00:00Z"),
                calendar: calendar))
    }
}
