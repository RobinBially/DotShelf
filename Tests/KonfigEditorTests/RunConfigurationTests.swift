import XCTest
@testable import KonfigEditor

final class RunConfigurationTests: XCTestCase {

    func testShellQuotingWrapsPathsAndEscapesSingleQuotes() {
        XCTAssertEqual(RunConfiguration.shellQuoted("/Users/robin/my scripts/build.sh"),
                       "'/Users/robin/my scripts/build.sh'")
        XCTAssertEqual(RunConfiguration.shellQuoted("/tmp/o'brien.sh"),
                       "'/tmp/o'\\''brien.sh'")
    }

    func testComposeFilesAreRecognisedByName() {
        for name in ["docker-compose.yml", "docker-compose.yaml", "compose.yaml", "COMPOSE.YML"] {
            let file = ConfigFile.custom(path: "/tmp/project/" + name)
            XCTAssertTrue(RunConfiguration.isComposeFile(file), name)
        }
        XCTAssertFalse(RunConfiguration.isComposeFile(ConfigFile.custom(path: "/tmp/config.yml")))
    }

    func testComposeSuggestionStartsTheStackInItsDirectory() {
        let file = ConfigFile.custom(path: "/tmp/project/docker-compose.yml")
        let suggestion = RunConfiguration.suggestion(for: file)
        XCTAssertEqual(suggestion.command, "docker compose -f '/tmp/project/docker-compose.yml' up")
        XCTAssertEqual(suggestion.workingDirectory.path, "/tmp/project")
        XCTAssertEqual(suggestion.name, "docker compose")
        XCTAssertEqual(suggestion.sourceFileID, file.id)
    }

    func testNonExecutableShellScriptRunsThroughZsh() {
        let file = ConfigFile.custom(path: "/tmp/project/deploy.sh")
        let suggestion = RunConfiguration.suggestion(for: file)
        XCTAssertEqual(suggestion.command, "zsh '/tmp/project/deploy.sh'")
        XCTAssertEqual(suggestion.workingDirectory.path, "/tmp/project")
    }

    func testExecutableShellScriptRunsDirectly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotshelf-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(RunConfiguration.suggestion(for: ConfigFile.custom(path: url.path)).command,
                       RunConfiguration.shellQuoted(url.path))
    }

    func testOtherFilesGetAnEmptyCommand() {
        let file = ConfigFile.custom(path: "/tmp/project/config.json")
        XCTAssertEqual(RunConfiguration.suggestion(for: file).command, "")
    }

    func testShellConfigurationIsNotOfferedAsAScript() throws {
        // .zshrc hat Shell-Highlighting, ist aber Konfiguration.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotshelf-\(UUID().uuidString).zshrc")
        try Data("export PATH=$PATH:/usr/local/bin\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = ConfigFile.custom(path: url.path)
        XCTAssertEqual(file.language, .shell)
        XCTAssertFalse(RunConfiguration.isScriptFile(file))
        XCTAssertEqual(RunConfiguration.suggestion(for: file).command, "")
    }

    func testExtensionlessFileWithShebangCountsAsAScript() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotshelf-\(UUID().uuidString)-runner")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = ConfigFile.custom(path: url.path)
        XCTAssertTrue(RunConfiguration.isScriptFile(file))
        XCTAssertEqual(RunConfiguration.suggestion(for: file).command,
                       "zsh " + RunConfiguration.shellQuoted(url.path))
    }

    func testScriptsAndComposeFilesGetAMatchingListSymbol() throws {
        XCTAssertEqual(ConfigFile.symbol(for: URL(fileURLWithPath: "/tmp/p/docker-compose.yml")),
                       "shippingbox")
        XCTAssertEqual(ConfigFile.symbol(for: URL(fileURLWithPath: "/tmp/p/compose.yaml")),
                       "shippingbox")
        XCTAssertEqual(ConfigFile.symbol(for: URL(fileURLWithPath: "/tmp/p/.zshrc")), "terminal")
        XCTAssertEqual(ConfigFile.symbol(for: URL(fileURLWithPath: "/tmp/p/config.json")), "curlybraces")
        XCTAssertEqual(ConfigFile.symbol(for: URL(fileURLWithPath: "/tmp/p/notes.md")), "doc.text")

        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotshelf-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        XCTAssertEqual(ConfigFile.symbol(for: script), "terminal")
        XCTAssertEqual(ConfigFile.custom(path: script.path).symbol, "terminal")
        XCTAssertEqual(ConfigFile.custom(path: script.path).withSymbol("hammer").symbol, "hammer")
    }
}
