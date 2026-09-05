import AppKit
import XCTest
@testable import KonfigEditor

final class SyntaxHighlighterTests: XCTestCase {
    @MainActor
    func testJSONCCommentMarkersInsideStringsKeepStringColor() throws {
        let source = #"{"url":"https://example.test/a//b", "note":"/* literal */"} // actual comment"#
        let storage = NSTextStorage(string: source)
        SyntaxHighlighter(font: .monospacedSystemFont(ofSize: 13, weight: .regular))
            .highlight(storage, language: .jsonc)
        for value in ["https://example.test/a//b", "/* literal */"] {
            let range = (source as NSString).range(of: value)
            XCTAssertEqual(storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor,
                           SyntaxTheme.string)
        }
        let comment = (source as NSString).range(of: "// actual comment")
        XCTAssertEqual(storage.attribute(.foregroundColor, at: comment.location, effectiveRange: nil) as? NSColor,
                       SyntaxTheme.comment)
    }
}
