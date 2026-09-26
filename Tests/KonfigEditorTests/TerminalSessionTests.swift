import XCTest
@testable import KonfigEditor

/// Prüft die echte PTY-Ausführung: Ausgabe, Exit-Status, Eingaben und Stoppen.
final class TerminalSessionTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotShelfTerminalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// Eigene Umgebung: eine Login-Shell ohne echtes HOME bleibt schnell und
    /// liest keine persönlichen Profile.
    private var testEnvironment: [String: String] {
        ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
         "HOME": directory.path,
         "LANG": "en_US.UTF-8"]
    }

    @MainActor
    private func session(_ command: String, name: String = "test",
                         kind: RunConfiguration.Kind = .command) -> TerminalSession {
        TerminalSession(
            configuration: RunConfiguration(name: name, command: command,
                                            workingDirectory: directory, kind: kind),
            columns: 80,
            environment: testEnvironment)
    }

    @MainActor
    private func waitFor(_ description: String, timeout: TimeInterval = 20,
                         _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    @MainActor
    func testRunsACommandAndReportsItsExitCode() async {
        let session = session("echo hello")
        session.start()
        await waitFor("the command to finish") { !session.isRunning }

        XCTAssertEqual(session.status, .exited(code: 0, stopped: false))
        XCTAssertFalse(session.hasFailed)
        // Der Befehlsheader darf die Ausgabe nicht einrücken.
        XCTAssertEqual(session.plainText, "$ echo hello\nhello")
    }

    @MainActor
    func testReportsANonZeroExitCodeAsFailure() async {
        let session = session("echo trouble >&2; exit 3")
        session.start()
        await waitFor("the command to finish") { !session.isRunning }

        XCTAssertEqual(session.status, .exited(code: 3, stopped: false))
        XCTAssertTrue(session.hasFailed)
        XCTAssertTrue(session.plainText.contains("trouble"))
    }

    @MainActor
    func testReadsInputSentToTheTerminal() async {
        let session = session("read line; echo got:$line")
        session.start()
        await waitFor("the shell to start reading") { session.isRunning }
        session.send(Data("value\n".utf8))
        await waitFor("the command to finish") { !session.isRunning }

        XCTAssertEqual(session.status, .exited(code: 0, stopped: false))
        XCTAssertTrue(session.plainText.contains("got:value"))
    }

    @MainActor
    func testStoppingAScriptDoesNotCountAsFailure() async {
        let session = session("sleep 30")
        session.start()
        await waitFor("the script to start") { session.isRunning }
        session.stop()
        await waitFor("the script to stop") { !session.isRunning }

        XCTAssertFalse(session.hasFailed)
        XCTAssertEqual(session.statusText, "Stopped")
    }

    @MainActor
    func testStoppingAnInteractiveShellEndsIt() async {
        // Interaktive Shells fangen SIGINT und SIGTERM ab: ohne die harte
        // Eskalation bliebe der Stop-Button ohne Wirkung.
        let session = session("exec /bin/zsh -l -i", name: "Shell", kind: .shell)
        session.start()
        // Erst warten, bis die Shell wirklich arbeitet (Prompt ist da).
        await waitFor("the shell prompt") { session.plainText.contains(" %") }
        XCTAssertTrue(session.isRunning, "Shell lief nicht: \(session.statusText)")

        let started = Date()
        session.stop()
        await waitFor("the shell to stop", timeout: 10) { !session.isRunning }

        XCTAssertLessThan(Date().timeIntervalSince(started), 5,
                          "Stop muss zügig wirken statt sekundenlang zu warten")
        XCTAssertEqual(session.statusText, "Stopped")
        XCTAssertFalse(session.hasFailed)
    }

    @MainActor
    func testAShellCountsAsReadyUntilACommandRunsInIt() async {
        let session = session("exec /bin/zsh -l -i", name: "Shell", kind: .shell)
        session.start()
        await waitFor("the shell prompt") { session.plainText.contains(" %") }
        // Der Start räumt noch auf (Login-Profile): warten, bis wirklich Ruhe
        // an der Eingabeaufforderung ist.
        await waitFor("the shell to be idle") { !session.isBusy }

        // Nur an der Eingabeaufforderung zu stehen ist keine Arbeit: kein
        // Rädchen, sondern „Ready“.
        XCTAssertFalse(session.isBusy)
        XCTAssertEqual(session.statusText, "Ready")

        session.send(Data("sleep 5\n".utf8))
        await waitFor("the command inside the shell") { session.isBusy }
        XCTAssertEqual(session.statusText, "Running…")

        session.send(Data("exit\n".utf8))
        await waitFor("the shell to end") { !session.isRunning }
        XCTAssertFalse(session.isBusy)
    }

    @MainActor
    func testRerunClearsThePreviousOutput() async {
        let session = session("echo run")
        session.start()
        await waitFor("the first run") { !session.isRunning }
        session.rerun()
        await waitFor("the second run") { !session.isRunning }

        XCTAssertEqual(session.status, .exited(code: 0, stopped: false))
        XCTAssertEqual(session.plainText.components(separatedBy: "$ echo run").count - 1, 1)
        XCTAssertTrue(session.plainText.hasSuffix("run"))
    }

    @MainActor
    func testWorkingDirectoryIsUsed() async {
        // Breite 200: der temporäre Pfad passt in eine Zeile, ohne Umbruch.
        let session = TerminalSession(
            configuration: RunConfiguration(name: "pwd", command: "pwd",
                                            workingDirectory: directory),
            columns: 200,
            environment: testEnvironment)
        session.start()
        await waitFor("the command to finish") { !session.isRunning }

        // Die Shell meldet den aufgelösten Pfad (/private/var/... statt /var/...).
        let resolved = directory.resolvingSymlinksInPath().path
        XCTAssertTrue(session.plainText.contains(resolved),
                      "status=\(session.status) text=\(session.plainText)")
    }

    @MainActor
    func testEmptyCommandDoesNotStartASession() {
        let store = Store(initialFiles: [], newFileDirectory: directory)
        XCTAssertNil(store.run(RunConfiguration(name: "x", command: "   ",
                                                workingDirectory: directory)))
        XCTAssertTrue(store.sessions.isEmpty)
    }
}
