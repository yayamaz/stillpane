import CoreGraphics
import XCTest

@testable import StillpaneCore

final class WindowSelectorTests: XCTestCase {
    private let activePID: Int32 = 100
    private let ownPID: Int32 = 999

    private func entry(
        pid: Int32, layer: Int = 0, id: UInt32,
        bounds: CGRect? = CGRect(x: 0, y: 0, width: 800, height: 600),
        alpha: Double = 1, title: String? = nil
    ) -> WindowListEntry {
        WindowListEntry(
            ownerPID: pid, layer: layer, windowID: id, bounds: bounds,
            alpha: alpha, title: title)
    }

    // MARK: - Primary path (byte-compatible with the original picker)

    func testActiveAppsFirstNormalWindowWinsInFrontToBackOrder() {
        let selection = WindowSelector.select(
            entries: [
                entry(pid: 200, id: 1),
                entry(pid: activePID, id: 2),
                entry(pid: activePID, id: 3),
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertEqual(selection?.entry.windowID, 2)
        XCTAssertEqual(selection?.isFallback, false)
    }

    func testPrimarySkipsTheActiveAppsElevatedWindows() {
        let selection = WindowSelector.select(
            entries: [
                entry(pid: activePID, layer: 25, id: 1),
                entry(pid: activePID, id: 2),
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertEqual(selection?.entry.windowID, 2)
        XCTAssertEqual(selection?.isFallback, false)
    }

    /// The original picker applied no alpha or size filters to the active
    /// app's windows; the primary path keeps that exactly.
    func testPrimaryAppliesNoAlphaOrSizeFilters() {
        let selection = WindowSelector.select(
            entries: [
                entry(
                    pid: activePID, id: 1,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1), alpha: 0)
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertEqual(selection?.entry.windowID, 1)
        XCTAssertEqual(selection?.isFallback, false)
    }

    // MARK: - Fallback (activation theft)

    func testFallsBackToTopmostNormalWindowWhenActiveAppHasOnlyElevatedWindows() {
        let selection = WindowSelector.select(
            entries: [
                // The recorder's control strip: elevated, active app.
                entry(pid: activePID, layer: 25, id: 1),
                // The article the user is reading.
                entry(pid: 200, id: 2),
                entry(pid: 300, id: 3),
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertEqual(selection?.entry.windowID, 2)
        XCTAssertEqual(selection?.isFallback, true)
    }

    func testFallbackSkipsOurOwnWindows() {
        let selection = WindowSelector.select(
            entries: [
                entry(pid: ownPID, id: 1),
                entry(pid: 200, id: 2),
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertEqual(selection?.entry.windowID, 2)
        XCTAssertEqual(selection?.isFallback, true)
    }

    func testFallbackSkipsInvisibleAndHelperWindows() {
        let selection = WindowSelector.select(
            entries: [
                entry(pid: 200, id: 1, alpha: 0),
                entry(pid: 300, id: 2, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
                entry(pid: 400, id: 3, bounds: nil),
                entry(pid: 500, id: 4),
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertEqual(selection?.entry.windowID, 4)
        XCTAssertEqual(selection?.isFallback, true)
    }

    func testFallbackSkipsElevatedWindowsOfOtherApps() {
        let selection = WindowSelector.select(
            entries: [
                entry(pid: 200, layer: 3, id: 1),
                entry(pid: 300, id: 2),
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertEqual(selection?.entry.windowID, 2)
        XCTAssertEqual(selection?.isFallback, true)
    }

    func testNothingEligibleReturnsNil() {
        let selection = WindowSelector.select(
            entries: [
                entry(pid: activePID, layer: 25, id: 1),
                entry(pid: ownPID, id: 2),
                entry(pid: 300, id: 3, alpha: 0),
            ],
            activePID: activePID, ownPID: ownPID
        )
        XCTAssertNil(selection)
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(
            WindowSelector.select(entries: [], activePID: activePID, ownPID: ownPID))
    }

    // MARK: - Matching the focused AX window back to a CG entry

    private let axFrame = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testMatchEntryReturnsTheGeometricMatch() {
        let match = WindowSelector.matchEntry(
            axFrame: axFrame, axTitle: nil,
            entries: [
                entry(pid: activePID, id: 1, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
                entry(pid: activePID, id: 2, bounds: axFrame),
            ],
            activePID: activePID
        )
        XCTAssertEqual(match?.windowID, 2)
    }

    func testMatchEntryToleratesTwoPointsButNotThree() {
        let nudged = CGRect(x: 102, y: 98, width: 802, height: 598)
        let entries = [entry(pid: activePID, id: 1, bounds: nudged)]
        XCTAssertEqual(
            WindowSelector.matchEntry(
                axFrame: axFrame, axTitle: nil, entries: entries, activePID: activePID
            )?.windowID, 1)
        let far = CGRect(x: 103, y: 100, width: 800, height: 600)
        XCTAssertNil(
            WindowSelector.matchEntry(
                axFrame: axFrame, axTitle: nil,
                entries: [entry(pid: activePID, id: 1, bounds: far)],
                activePID: activePID
            ))
    }

    func testMatchEntryIgnoresOtherAppsAndElevatedLayers() {
        let match = WindowSelector.matchEntry(
            axFrame: axFrame, axTitle: nil,
            entries: [
                entry(pid: 200, id: 1, bounds: axFrame),
                entry(pid: activePID, layer: 3, id: 2, bounds: axFrame),
            ],
            activePID: activePID
        )
        XCTAssertNil(match)
    }

    func testMatchEntryBreaksGeometryTiesByTitle() {
        let match = WindowSelector.matchEntry(
            axFrame: axFrame, axTitle: "Notes",
            entries: [
                entry(pid: activePID, id: 1, bounds: axFrame, title: "Scratch"),
                entry(pid: activePID, id: 2, bounds: axFrame, title: "Notes"),
            ],
            activePID: activePID
        )
        XCTAssertEqual(match?.windowID, 2)
    }

    func testMatchEntryWithoutTitlesTakesTheTopmostTwin() {
        let match = WindowSelector.matchEntry(
            axFrame: axFrame, axTitle: "Notes",
            entries: [
                entry(pid: activePID, id: 1, bounds: axFrame),
                entry(pid: activePID, id: 2, bounds: axFrame),
            ],
            activePID: activePID
        )
        XCTAssertEqual(match?.windowID, 1)
    }
}
