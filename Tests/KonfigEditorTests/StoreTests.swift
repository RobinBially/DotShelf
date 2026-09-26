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
                       directory: URL? = nil, commentRemoval: Bool = false,
                       stopRunning: Bool = true) -> Store {
        Store(initialFiles: files, defaults: defaults, newFileDirectory: directory ?? self.directory,
              pendingChangesDecision: { _ in decision }, confirmCommentRemoval: { commentRemoval },
              confirmStopRunning: { stopRunning })
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
        XCTAssertEqual(editor.selection, .file(a.id))
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
        XCTAssertEqual(editor.selection, .file(a.id))
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
        XCTAssertEqual(editor.selection, .file(b.id))
        XCTAssertEqual(try String(contentsOf: a.url, encoding: .utf8), "saved edit")
        let discarding = store([a, b], decision: .discard)
        discarding.text = "discarded edit"
        discarding.reload()
        XCTAssertEqual(discarding.text, "saved edit")
        discarding.text = "another edit"
        discarding.removeFile(a)
        XCTAssertEqual(discarding.selection, .file(b.id))
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
        XCTAssertEqual(editor.selection, .file(a.id))
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

    @MainActor
    func testRunCreatesATemporaryTerminalEntryAndKeepsTheEditBuffer() throws {
        let script = try file("script.sh", "echo hi")
        let editor = store([script])
        editor.text = "echo edited"
        let session = try XCTUnwrap(editor.run(RunConfiguration(
            name: "script.sh", command: "echo edited",
            workingDirectory: directory, sourceFileID: script.id)))

        XCTAssertEqual(editor.sessions.count, 1)
        XCTAssertEqual(editor.selection, .terminal(session.id))
        XCTAssertNil(editor.selectedFile)
        XCTAssertEqual(editor.selectedTerminal?.id, session.id)
        // Der bearbeitete Befehl wird vor dem Start gespeichert.
        XCTAssertEqual(try String(contentsOf: script.url, encoding: .utf8), "echo edited")

        // Zurück zur Datei: der Puffer bleibt erhalten, ohne Nachfrage.
        editor.text = "unsaved edit"
        editor.selectFromSidebar(script.id)
        XCTAssertEqual(editor.selection, .file(script.id))
        XCTAssertEqual(editor.text, "unsaved edit")

        editor.closeSession(session)
        XCTAssertTrue(editor.sessions.isEmpty)
        XCTAssertEqual(editor.selection, .file(script.id))
    }

    @MainActor
    func testCancelledCloseKeepsTheTerminalEntry() throws {
        let editor = store([], stopRunning: false)
        let session = try XCTUnwrap(editor.run(RunConfiguration(
            name: "sleep", command: "sleep 30", workingDirectory: directory)))
        editor.closeSession(session)
        XCTAssertEqual(editor.sessions.count, 1)
        XCTAssertEqual(editor.selection, .terminal(session.id))
        session.stop()
    }

    @MainActor
    func testRunSuggestionFollowsTheFileType() throws {
        let shell = try file("deploy.sh", "echo hi")
        let compose = try file("docker-compose.yml", "services: {}\n")
        let editor = store([shell, compose])

        let shellSuggestion = editor.suggestedRunConfiguration(for: shell)
        XCTAssertEqual(shellSuggestion.command, "zsh " + RunConfiguration.shellQuoted(shell.url.path))
        XCTAssertEqual(shellSuggestion.workingDirectory.path, directory.path)

        let composeSuggestion = editor.suggestedRunConfiguration(for: compose)
        XCTAssertEqual(composeSuggestion.command,
                       "docker compose -f " + RunConfiguration.shellQuoted(compose.url.path) + " up")
        XCTAssertEqual(composeSuggestion.sourceFileID, compose.id)

        editor.presentRunSheet(for: compose)
        XCTAssertEqual(editor.runDraft?.command, composeSuggestion.command)
        editor.runDraft = nil

        editor.presentRunSheetWithoutSuggestion()
        XCTAssertEqual(editor.runDraft?.command, "")
        XCTAssertEqual(editor.runDraft?.workingDirectory.path, directory.path)
    }

    @MainActor
    func testClosingAnIdleTerminalAsksNothing() async throws {
        var asked = false
        let editor = Store(initialFiles: [], defaults: defaults, newFileDirectory: directory,
                           pendingChangesDecision: { _ in .cancel },
                           confirmCommentRemoval: { false },
                           confirmStopRunning: { asked = true; return false })

        let session = try XCTUnwrap(editor.run(RunConfiguration(
            name: "Shell", command: "exec /bin/zsh -l -i",
            workingDirectory: directory, kind: .shell)))
        // Warten, bis die Shell nur noch an der Eingabeaufforderung steht.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !(session.isRunning && !session.isBusy) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(session.isRunning && !session.isBusy,
                      "Shell wurde nicht bereit: \(session.statusText)")

        editor.closeSession(session)
        XCTAssertFalse(asked, "Ein Terminal im Leerlauf braucht keine Rückfrage")
        XCTAssertTrue(editor.sessions.isEmpty)
    }

    @MainActor
    func testClosingABusyTerminalAsksFirst() throws {
        var asked = false
        let editor = Store(initialFiles: [], defaults: defaults, newFileDirectory: directory,
                           pendingChangesDecision: { _ in .cancel },
                           confirmCommentRemoval: { false },
                           confirmStopRunning: { asked = true; return false })

        let session = try XCTUnwrap(editor.run(RunConfiguration(
            name: "lang", command: "sleep 30", workingDirectory: directory)))
        XCTAssertTrue(session.isBusy)

        editor.closeSession(session)
        XCTAssertTrue(asked, "Bei laufendem Prozess muss gefragt werden")
        XCTAssertEqual(editor.sessions.count, 1, "Abbruch darf den Eintrag behalten")
        session.stop()
    }
}
