import AppKit
import XCTest
@testable import KonfigEditor

final class TerminalBufferTests: XCTestCase {

    private func buffer(columns: Int = TerminalBuffer.defaultColumns) -> TerminalBuffer {
        TerminalBuffer(columns: columns)
    }

    private func feed(_ buffer: TerminalBuffer, _ text: String) {
        buffer.feed(Data(text.utf8))
    }

    func testPlainTextKeepsLineBreaksAndDropsTrailingSpaces() {
        let terminal = buffer()
        feed(terminal, "first   \r\nsecond\r\n")
        XCTAssertEqual(terminal.plainText, "first\nsecond")
    }

    func testColorSequencesAreRemovedFromText() {
        let terminal = buffer()
        feed(terminal, "\u{1B}[1;32mok\u{1B}[0m done")
        XCTAssertEqual(terminal.plainText, "ok done")
    }

    func testCarriageReturnOverwritesTheCurrentLine() {
        let terminal = buffer()
        feed(terminal, "12345\rAB")
        XCTAssertEqual(terminal.plainText, "AB345")
    }

    func testCarriageReturnKeepsProgressUpdatesOnOneLine() {
        let terminal = buffer()
        feed(terminal, "Download 10%\rDownload 100%")
        XCTAssertEqual(terminal.plainText, "Download 100%")
    }

    func testLongLinesWrapAtTheConfiguredWidth() {
        let terminal = buffer(columns: 20)
        feed(terminal, String(repeating: "x", count: 25))
        XCTAssertEqual(terminal.plainText, String(repeating: "x", count: 20)
                       + "\n" + String(repeating: "x", count: 5))
    }

    func testEraseAndCursorUpReplaceAnEarlierLine() {
        let terminal = buffer()
        feed(terminal, "line1\r\nline2\r\n\u{1B}[1A\u{1B}[2Knew")
        XCTAssertEqual(terminal.plainText, "line1\nnew")
    }

    func testCarriageReturnWithEraseToEndOfLineRewritesTheLine() {
        let terminal = buffer()
        feed(terminal, "building\r\u{1B}[Kvalidating")
        XCTAssertEqual(terminal.plainText, "validating")
    }

    func testSplitUTF8SequenceIsCompletedAcrossChunks() {
        let terminal = buffer()
        let bytes = Array("grün".utf8)
        terminal.feed(Data(bytes[0..<3]))
        terminal.feed(Data(bytes[3...]))
        XCTAssertEqual(terminal.plainText, "grün")
    }

    func testCursorVisibilityModesAreHonoured() {
        let terminal = buffer()
        feed(terminal, "\u{1B}[?25l")
        XCTAssertFalse(terminal.cursorVisible)
        feed(terminal, "\u{1B}[?25h")
        XCTAssertTrue(terminal.cursorVisible)
    }

    func testClearResetsTheOutput() {
        let terminal = buffer()
        feed(terminal, "noise\r\n")
        terminal.clear()
        XCTAssertEqual(terminal.plainText, "")
    }

    func testAttributedStringCarriesColorsAndCachesTheResult() {
        let terminal = buffer()
        feed(terminal, "\u{1B}[31mred\u{1B}[0m plain")
        let rendered = terminal.attributedString(showCursor: false, fontSize: 12)
        XCTAssertEqual(rendered.string, "red plain\n")
        let redRange = (rendered.string as NSString).range(of: "red")
        let color = rendered.attribute(.foregroundColor, at: redRange.location, effectiveRange: nil)
        XCTAssertNotEqual(color as? NSColor, TerminalTheme.foreground)
        XCTAssertTrue(terminal.attributedString(showCursor: false, fontSize: 12) === rendered)
    }

    func testWrappingThenNewlineDoesNotAddABlankLine() {
        let terminal = buffer(columns: 20)
        feed(terminal, String(repeating: "a", count: 20) + "\r\nb")
        XCTAssertEqual(terminal.plainText, String(repeating: "a", count: 20) + "\nb")
    }
}
