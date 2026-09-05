import XCTest
@testable import KonfigEditor

final class StoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DotShelfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "DotShelfTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String, _ content: String = "original") throws -> ConfigFile {
        let url = directory.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return ConfigFile.custom(path: url.path)
    }

    @MainActor
    private func store(_ files: [ConfigFile], decision: Store.PendingChangesDecision = .cancel,
                       directory: URL? = nil, commentRemoval: Bool = false) -> Store {
        Store(initialFiles: files, defaults: defaults, newFileDirectory: directory ?? self.directory,
              pendingChangesDecision: { _ in decision }, confirmCommentRemoval: { commentRemoval })
    }

    @MainActor
    func testCancelProtectsEveryDestructiveTransition() throws {
        let a = try file("a.txt"), b = try file("b.txt")
        let editor = store([a, b])
        editor.text = "unsaved"
        editor.selectFromSidebar(b.id)
        editor.reload()
        editor.addFile(url: directory.appendingPathComponent("c.txt"))
        editor.createEmptyFile()
        editor.removeFile(a)
        XCTAssertFalse(editor.confirmPendingChanges())
        XCTAssertEqual(editor.selection, a.id)
        XCTAssertEqual(editor.text, "unsaved")
        XCTAssertEqual(editor.files.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("untitled.txt").path))
    }

    @MainActor
    func testFailedSavePreventsSwitchAndRetainsErrorAndBuffer() throws {
        let a = try file("a.txt"), b = try file("b.txt")
        let editor = store([a, b], decision: .save)
        editor.text = "unsaved"
        try Data("external".utf8).write(to: a.url)
        editor.selectFromSidebar(b.id)
        XCTAssertEqual(editor.selection, a.id)
        XCTAssertEqual(editor.text, "unsaved")
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertNotNil(editor.lastError)
        XCTAssertFalse(editor.confirmPendingChanges())
        XCTAssertEqual(try String(contentsOf: a.url, encoding: .utf8), "external")
    }

    @MainActor
    func testSaveAndDiscardTransitions() throws {
        let a = try file("a.txt"), b = try file("b.txt", "second")
        let editor = store([a, b], decision: .save)
        editor.text = "saved edit"
        editor.select(b)
        XCTAssertEqual(editor.selection, b.id)
        XCTAssertEqual(try String(contentsOf: a.url, encoding: .utf8), "saved edit")
        let discarding = store([a, b], decision: .discard)
        discarding.text = "discarded edit"
        discarding.reload()
        XCTAssertEqual(discarding.text, "saved edit")
        discarding.text = "another edit"
        discarding.removeFile(a)
        XCTAssertEqual(discarding.selection, b.id)
        XCTAssertEqual(discarding.text, "second")
    }

    @MainActor
    func testLiveValidationAndFormattingCommentConfirmation() throws {
        let json = try file("a.json", "{}")
        let editor = store([json])
        XCTAssertEqual(editor.validation, .valid)
        editor.text = "{invalid"
        guard case .invalid = editor.validation else { return XCTFail("Validation was not updated") }
        editor.text = "true"
        editor.formatJSON()
        XCTAssertEqual(editor.text, "true")
        let jsonc = try file("a.jsonc", "// comment\r\n{\"x\":1,}")
        let cancelled = store([jsonc])
        let original = cancelled.text
        cancelled.formatJSON()
        XCTAssertEqual(cancelled.text, original)
        let approved = store([jsonc], commentRemoval: true)
        approved.formatJSON()
        XCTAssertFalse(approved.text.contains("//"))
        XCTAssertTrue(approved.hasUnsavedChanges)
        XCTAssertEqual(try String(contentsOf: jsonc.url, encoding: .utf8), original)
    }

    @MainActor
    func testRenamingMissingSourceCannotAdoptExistingTarget() throws {
        let a = try file("a.txt"), b = try file("b.txt", "preserved")
        let editor = store([a])
        editor.text = "unsaved"
        try FileManager.default.removeItem(at: a.url)
        editor.renameFile(a, to: "b.txt")
        XCTAssertEqual(editor.selectedFile?.url, a.url)
        XCTAssertNotNil(editor.lastError)
        XCTAssertFalse(editor.save())
        XCTAssertEqual(try String(contentsOf: b.url, encoding: .utf8), "preserved")
    }

    @MainActor
    func testCreateFailureDoesNotAddEntryOrClaimSuccess() throws {
        let a = try file("a.txt")
        let invalidDirectory = try file("not-a-directory").url
        let editor = store([a], directory: invalidDirectory)
        editor.createEmptyFile()
        XCTAssertEqual(editor.files.count, 1)
        XCTAssertEqual(editor.selection, a.id)
        XCTAssertNotNil(editor.lastError)
    }

    @MainActor
    func testCreateSuccessAndLanguageChangeOnRename() throws {
        let editor = store([])
        editor.createEmptyFile()
        let created = try XCTUnwrap(editor.selectedFile)
        XCTAssertTrue(created.exists)
        editor.text = "{invalid"
        editor.renameFile(created, to: "config.json")
        XCTAssertEqual(editor.selectedFile?.language, .json)
        XCTAssertEqual(editor.text, "{invalid")
        guard case .invalid = editor.validation else { return XCTFail("Language change did not revalidate") }
        XCTAssertTrue(editor.save())
    }
}
