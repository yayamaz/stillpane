import XCTest

@testable import StillpaneCore

final class OnboardingStepTests: XCTestCase {
    func testFlowStartsAtWelcomeAndEndsAtDone() {
        XCTAssertEqual(OnboardingStep.allCases.first, .welcome)
        XCTAssertEqual(OnboardingStep.allCases.last, .done)
    }

    func testNextWalksEveryStepInOrder() {
        var visited: [OnboardingStep] = [.welcome]
        var current = OnboardingStep.welcome
        while let next = current.next {
            visited.append(next)
            current = next
        }
        XCTAssertEqual(visited, OnboardingStep.allCases)
    }

    func testNextIsNilAtTheEnd() {
        XCTAssertNil(OnboardingStep.done.next)
    }

    func testIndicatorStepsExcludeDone() {
        XCTAssertEqual(
            OnboardingStep.indicatorSteps,
            [.welcome, .accessibility, .screenRecording, .claudeCode, .tryIt]
        )
    }

    func testIndicatorIndexMatchesPositionInTheIndicator() {
        for (offset, step) in OnboardingStep.indicatorSteps.enumerated() {
            XCTAssertEqual(step.indicatorIndex, offset, "\(step)")
        }
    }

    func testDoneIsPastEveryIndicatorStep() {
        for step in OnboardingStep.indicatorSteps {
            XCTAssertTrue(OnboardingStep.done.isPast(step), "\(step)")
        }
    }

    func testIsPastIsFalseForTheCurrentAndLaterSteps() {
        XCTAssertFalse(OnboardingStep.screenRecording.isPast(.screenRecording))
        XCTAssertFalse(OnboardingStep.screenRecording.isPast(.claudeCode))
        XCTAssertTrue(OnboardingStep.screenRecording.isPast(.accessibility))
    }

    func testEveryStepHasATitle() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step)")
        }
    }
}
