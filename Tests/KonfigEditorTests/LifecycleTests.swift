import AppKit
import XCTest
@testable import KonfigEditor

final class LifecycleTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotShelfLifecycleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "DotShelfLifecycleTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }

    private func file() throws -> ConfigFile {
        let url = directory.appendingPathComponent("config.txt")
        try Data("original".utf8).write(to: url)
        return ConfigFile.custom(path: url.path)
    }

    @MainActor
    private func store(_ file: ConfigFile,
                       decision: @escaping (ConfigFile) -> Store.PendingChangesDecision) -> Store {
        Store(initialFiles: [file], defaults: defaults, newFileDirectory: directory,
              pendingChangesDecision: decision)
    }

    @MainActor
    private func hiddenWindow() -> NSWindow {
        _ = NSApplication.shared
        return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.titled, .closable], backing: .buffered, defer: true)
    }

    @MainActor
    func testCancelBlocksCloseAndQuitWithoutChangingFile() throws {
        let file = try file()
        var decisions = 0
        let editor = store(file) { _ in decisions += 1; return .cancel }
        editor.text = "unsaved"
        let lifecycle = DotShelfAppDelegate()
        lifecycle.store = editor
        let coordinator = WindowConfigurator.Coordinator(appDelegate: lifecycle)

        XCTAssertFalse(coordinator.windowShouldClose(hiddenWindow()))
        XCTAssertEqual(lifecycle.applicationShouldTerminate(.shared), .terminateCancel)
        XCTAssertEqual(decisions, 2)
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertEqual(editor.text, "unsaved")
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8), "original")
    }

    @MainActor
    func testSaveConflictBlocksCloseAndQuitAndPreservesBothVersions() throws {
        let file = try file()
        var decisions = 0
        let editor = store(file) { _ in decisions += 1; return .save }
        editor.text = "unsaved"
        try Data("external edit".utf8).write(to: file.url)
        let lifecycle = DotShelfAppDelegate()
        lifecycle.store = editor
        let coordinator = WindowConfigurator.Coordinator(appDelegate: lifecycle)

        XCTAssertFalse(coordinator.windowShouldClose(hiddenWindow()))
        XCTAssertEqual(lifecycle.applicationShouldTerminate(.shared), .terminateCancel)
        XCTAssertEqual(decisions, 2)
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertEqual(editor.text, "unsaved")
        XCTAssertNotNil(editor.lastError)
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8), "external edit")
    }

    @MainActor
    func testCancelledQuitCanBeRetriedWithSuccessfulSave() throws {
        let file = try file()
        var decision = Store.PendingChangesDecision.cancel
        var decisions = 0
        let editor = store(file) { _ in decisions += 1; return decision }
        editor.text = "saved edit"
        let lifecycle = DotShelfAppDelegate()
        lifecycle.store = editor

        XCTAssertEqual(lifecycle.applicationShouldTerminate(.shared), .terminateCancel)
        decision = .save
        XCTAssertEqual(lifecycle.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertEqual(decisions, 2)
        XCTAssertFalse(editor.hasUnsavedChanges)
        XCTAssertNil(editor.lastError)
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8), "saved edit")
    }

    @MainActor
    func testDiscardedCloseThenQuitAsksExactlyOnce() throws {
        let file = try file()
        var decisions = 0
        let editor = store(file) { _ in decisions += 1; return .discard }
        editor.text = "discarded edit"
        let lifecycle = DotShelfAppDelegate()
        lifecycle.store = editor
        let coordinator = WindowConfigurator.Coordinator(appDelegate: lifecycle)

        XCTAssertTrue(coordinator.windowShouldClose(hiddenWindow()))
        // Discard approval leaves the Store buffer dirty until the app exits.
        // Therefore this verifies the lifecycle guard, not just Store's clean path.
        XCTAssertTrue(editor.hasUnsavedChanges)
        XCTAssertTrue(lifecycle.applicationShouldTerminateAfterLastWindowClosed(.shared))
        XCTAssertEqual(lifecycle.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertEqual(decisions, 1)
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8), "original")
    }

    @MainActor
    func testFailedSaveCanBeRetriedWithDiscard() throws {
        let file = try file()
        var decision = Store.PendingChangesDecision.save
        var decisions = 0
        let editor = store(file) { _ in decisions += 1; return decision }
        editor.text = "unsaved"
        try Data("external edit".utf8).write(to: file.url)
        let lifecycle = DotShelfAppDelegate()
        lifecycle.store = editor
        let coordinator = WindowConfigurator.Coordinator(appDelegate: lifecycle)

        XCTAssertFalse(coordinator.windowShouldClose(hiddenWindow()))
        decision = .discard
        XCTAssertEqual(lifecycle.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertEqual(decisions, 2)
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8), "external edit")
    }

    @MainActor
    func testReentrantExitDoesNotOpenAnotherConfirmation() throws {
        let file = try file()
        let lifecycle = DotShelfAppDelegate()
        var decisions = 0
        let editor = store(file) { _ in
            decisions += 1
            XCTAssertFalse(lifecycle.confirmExit())
            return .cancel
        }
        editor.text = "unsaved"
        lifecycle.store = editor

        XCTAssertEqual(lifecycle.applicationShouldTerminate(.shared), .terminateCancel)
        XCTAssertEqual(decisions, 1)
        XCTAssertTrue(editor.hasUnsavedChanges)
    }
}
