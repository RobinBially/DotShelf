import XCTest
@testable import KonfigEditor

final class JSONDocumentTests: XCTestCase {
    func testFormattingPreservesStringContentsAndUnicode() throws {
        let source = #"{"message":"hello, }","url":"https://example.test/a, ]","escaped":"\"//not a comment","unicode":"🦊 ä" ,}"#
        let parsed = try JSONDocument.parse(source, allowsComments: true)
        let formatted = try JSONDocument.formatted(parsed.object)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(formatted.utf8)) as? [String: String])
        XCTAssertEqual(values["message"], "hello, }")
        XCTAssertEqual(values["url"], "https://example.test/a, ]")
        XCTAssertEqual(values["escaped"], "\"//not a comment")
        XCTAssertEqual(values["unicode"], "🦊 ä")
        XCTAssertFalse(parsed.hasComments)
    }

    func testScalarFormatting() throws {
        for source in ["true", "null", "42", #""hello""#] {
            let parsed = try JSONDocument.parse(source, allowsComments: false)
            XCTAssertEqual(try JSONDocument.formatted(parsed.object), source)
        }
    }

    func testCRLFAndCRCommentsPreserveFollowingContent() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let source = "// heading\(newline){\"x\":1, /* middle */\(newline)\"y\":2, // tail\(newline)}"
            let parsed = try JSONDocument.parse(source, allowsComments: true)
            XCTAssertTrue(parsed.hasComments)
            let object = try XCTUnwrap(parsed.object as? [String: Int])
            XCTAssertEqual(object, ["x": 1, "y": 2])
        }
    }

    func testStrictJSONRejectsCommentsTrailingCommasAndEmptyInput() {
        for source in ["", "   ", "// heading\n{}", "{/* comment */}", "[1,]", "{\"x\":1,}"] {
            XCTAssertThrowsError(try JSONDocument.parse(source, allowsComments: false), source)
        }
    }

    func testUnterminatedCommentsAndSeparatedTokensAreRejected() {
        for source in ["[, ]", "[1,,]", "{,}", "{\"x\":,}", "{}/* open", "/* open", "[1/* comment */2]", "{\"x\":tru/* comment */e}"] {
            XCTAssertThrowsError(try JSONDocument.parse(source, allowsComments: true), source)
        }
    }
}
