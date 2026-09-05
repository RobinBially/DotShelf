import XCTest
@testable import KonfigEditor

final class LocalizationTests: XCTestCase {
    func testPackagedEnglishResourcesExist() {
        XCTAssertEqual(L10n.bundle.developmentLocalization, "en")
        XCTAssertEqual(L10n.bundle.localizedString(forKey: "Configurations", value: "MISSING", table: nil), "Configurations")
        XCTAssertEqual(L10n.bundle.localizations, ["en"])
    }

    func testFormattingUsesLocalizedMessage() {
        XCTAssertEqual(L10n.format("New filename for “%@”:", "example.json"), "New filename for “example.json”:")
        XCTAssertEqual(L10n.format("%d lines", 5), "5 lines")
    }
}
