import XCTest

@testable import StillpaneCore

final class MarkdownRendererTests: XCTestCase {
    func testHeadingUsesAXValueLevel() {
        let node = AXNode(
            role: "AXHeading", value: "3",
            children: [
                AXNode(role: "AXStaticText", value: "Pricing")
            ])
        XCTAssertEqual(MarkdownRenderer.render(node), "### Pricing\n")
    }

    func testHeadingWithoutLevelDefaultsToH2() {
        let node = AXNode(role: "AXHeading", title: "Intro")
        XCTAssertEqual(MarkdownRenderer.render(node), "## Intro\n")
    }

    func testStaticTextBecomesParagraph() {
        let node = AXNode(role: "AXStaticText", value: "Hello world")
        XCTAssertEqual(MarkdownRenderer.render(node), "Hello world\n")
    }

    func testLinkRendersMarkdownLink() {
        let node = AXNode(
            role: "AXLink", url: "https://a.dev",
            children: [
                AXNode(role: "AXStaticText", value: "docs")
            ])
        XCTAssertEqual(MarkdownRenderer.render(node), "[docs](https://a.dev)\n")
    }

    func testButtonRendersCompactNotation() {
        let node = AXNode(role: "AXButton", title: "Send")
        XCTAssertEqual(MarkdownRenderer.render(node), "[Button: Send]\n")
    }

    func testTextAreaValueRenderedVerbatim() {
        let node = AXNode(role: "AXTextArea", value: "line one\nline two")
        XCTAssertEqual(MarkdownRenderer.render(node), "line one\nline two\n")
    }

    func testListRendersBullets() {
        let node = AXNode(
            role: "AXList",
            children: [
                AXNode(role: "AXStaticText", value: "alpha"),
                AXNode(role: "AXStaticText", value: "beta"),
            ])
        XCTAssertEqual(MarkdownRenderer.render(node), "- alpha\n- beta\n")
    }

    func testTableRendersMarkdownTable() {
        let row1 = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Name")]),
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Qty")]),
            ])
        let row2 = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Widget")]),
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "4")]),
            ])
        let table = AXNode(role: "AXTable", children: [row1, row2])
        XCTAssertEqual(
            MarkdownRenderer.render(table),
            "| Name | Qty |\n| --- | --- |\n| Widget | 4 |\n"
        )
    }

    func testUnknownContainerRecursesIntoChildren() {
        let node = AXNode(
            role: "AXGroup",
            children: [
                AXNode(role: "AXStaticText", value: "a"),
                AXNode(role: "AXGroup", children: [AXNode(role: "AXStaticText", value: "b")]),
            ])
        XCTAssertEqual(MarkdownRenderer.render(node), "a\n\nb\n")
    }

    func testEmptyNodesProduceNothing() {
        let node = AXNode(role: "AXGroup", children: [AXNode(role: "AXButton")])
        XCTAssertEqual(MarkdownRenderer.render(node), "")
    }

    func testImageRendersDescription() {
        let node = AXNode(role: "AXImage", title: "team photo")
        XCTAssertEqual(MarkdownRenderer.render(node), "[Image: team photo]\n")
    }

    func testHeadingLevelClampsBelowOne() {
        let node = AXNode(role: "AXHeading", title: "Top", value: "0")
        XCTAssertEqual(MarkdownRenderer.render(node), "# Top\n")
    }

    func testHeadingLevelClampsAboveSix() {
        let node = AXNode(role: "AXHeading", title: "Deep", value: "9")
        XCTAssertEqual(MarkdownRenderer.render(node), "###### Deep\n")
    }

    func testLinkWithoutURLRendersBareLabel() {
        let node = AXNode(
            role: "AXLink",
            children: [
                AXNode(role: "AXStaticText", value: "docs")
            ])
        XCTAssertEqual(MarkdownRenderer.render(node), "docs\n")
    }

    func testTextFieldRendersFieldNotation() {
        let node = AXNode(role: "AXTextField", title: "Email", value: "a@b.dev")
        XCTAssertEqual(MarkdownRenderer.render(node), "[Field Email: a@b.dev]\n")
    }

    func testCheckBoxUsesCheckboxControlName() {
        let node = AXNode(role: "AXCheckBox", title: "Remember me")
        XCTAssertEqual(MarkdownRenderer.render(node), "[Checkbox: Remember me]\n")
    }

    func testMultiLineCellIsFlattenedToOneLine() {
        let header = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Note")])
            ])
        let body = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "one\ntwo")])
            ])
        let table = AXNode(role: "AXTable", children: [header, body])
        XCTAssertEqual(
            MarkdownRenderer.render(table),
            "| Note |\n| --- |\n| one two |\n"
        )
    }

    func testMultiLineListItemIsFlattenedToOneLine() {
        let node = AXNode(
            role: "AXList",
            children: [
                AXNode(role: "AXStaticText", value: "alpha\nbeta")
            ])
        XCTAssertEqual(MarkdownRenderer.render(node), "- alpha beta\n")
    }

    func testRaggedRowIsPaddedToHeaderWidth() {
        let header = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Name")]),
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Qty")]),
            ])
        let short = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Widget")])
            ])
        let table = AXNode(role: "AXTable", children: [header, short])
        XCTAssertEqual(
            MarkdownRenderer.render(table),
            "| Name | Qty |\n| --- | --- |\n| Widget |  |\n"
        )
    }

    func testTableWithEmptyFirstRowUsesFirstRowWithCells() {
        let empty = AXNode(role: "AXRow")
        let header = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Name")])
            ])
        let body = AXNode(
            role: "AXRow",
            children: [
                AXNode(role: "AXCell", children: [AXNode(role: "AXStaticText", value: "Widget")])
            ])
        let table = AXNode(role: "AXTable", children: [empty, header, body])
        XCTAssertEqual(
            MarkdownRenderer.render(table),
            "| Name |\n| --- |\n| Widget |\n"
        )
    }

    func testConsecutiveDuplicateBlocksCollapse() {
        let node = AXNode(
            role: "AXGroup",
            children: [
                AXNode(role: "AXButton", title: "Next image"),
                AXNode(role: "AXButton", title: "Next image"),
                AXNode(role: "AXButton", title: "Next image"),
                AXNode(role: "AXStaticText", value: "caption"),
                AXNode(role: "AXButton", title: "Next image"),
            ])
        XCTAssertEqual(
            MarkdownRenderer.render(node),
            "[Button: Next image]\n\ncaption\n\n[Button: Next image]\n"
        )
    }

    private let noteText = "[Capture truncated: the window's text exceeded stillpane's size limits.]"

    func testOversizedOutputIsCappedWithOneTruncationNote() {
        let node = AXNode(
            role: "AXStaticText",
            value: String(repeating: "a", count: MarkdownRenderer.maxOutputBytes + 1000)
        )
        let output = MarkdownRenderer.render(node)
        XCTAssertLessThanOrEqual(
            output.utf8.count, MarkdownRenderer.maxOutputBytes + noteText.utf8.count + 3
        )
        XCTAssertTrue(output.hasSuffix("\n\n" + noteText + "\n"))
        XCTAssertEqual(output.components(separatedBy: noteText).count, 2, "exactly one note")
    }

    func testManyNodesCannotExceedTheOutputCeiling() {
        let children = (0..<3000).map { i in
            AXNode(role: "AXStaticText", value: String(repeating: "b\(i) ", count: 300))
        }
        let output = MarkdownRenderer.render(AXNode(role: "AXGroup", children: children))
        XCTAssertLessThanOrEqual(
            output.utf8.count, MarkdownRenderer.maxOutputBytes + noteText.utf8.count + 3
        )
        XCTAssertTrue(output.contains(noteText))
    }

    func testTruncationCutsOnCharacterBoundaries() {
        // Four-byte scalars straddle any byte-offset cut; the output must
        // still be built from whole characters, never replacement bytes.
        let node = AXNode(
            role: "AXStaticText",
            value: String(repeating: "😀", count: MarkdownRenderer.maxOutputBytes / 4 + 100)
        )
        let output = MarkdownRenderer.render(node)
        XCTAssertFalse(output.contains("\u{FFFD}"))
        let body = output.components(separatedBy: "\n")[0]
        XCTAssertTrue(body.allSatisfy { $0 == "😀" })
        XCTAssertLessThanOrEqual(body.utf8.count, MarkdownRenderer.maxOutputBytes)
    }

    func testReaderTruncationFlagAddsTheNoteToSmallOutput() {
        let node = AXNode(role: "AXStaticText", value: "tiny")
        XCTAssertEqual(
            MarkdownRenderer.render(node, truncated: true),
            "tiny\n\n" + noteText + "\n"
        )
        XCTAssertEqual(
            MarkdownRenderer.render(AXNode(role: "AXGroup"), truncated: true),
            noteText + "\n",
            "a fully truncated capture still says so"
        )
    }
}
