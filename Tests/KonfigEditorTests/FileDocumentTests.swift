import XCTest
@testable import KonfigEditor

final class FileDocumentTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DotShelfDiskTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func write(_ name: String, _ content: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    func testSymlinkSaveKeepsLinkContentPermissionsAndIndependentBackups() throws {
        let target = try write("target.json", "{\"value\":1}")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let first = try FileDocument.read(link)
        let second = try first.write("{\"value\":2}", at: link, backup: true)
        _ = try second.write("{\"value\":3}", at: link, backup: true)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "{\"value\":3}")
        let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "bak" }
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(try Set(backups.map { try String(contentsOf: $0, encoding: .utf8) }), ["{\"value\":1}", "{\"value\":2}"])
        for backup in backups {
            let attrs = try FileManager.default.attributesOfItem(atPath: backup.path)
            XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeRegular)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testExternalEditAndDeletionAreNeverOverwritten() throws {
        let url = try write("config", "initial")
        let original = try FileDocument.read(url)
        try Data("external".utf8).write(to: url)
        XCTAssertThrowsError(try original.write("editor", at: url, backup: false))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external")
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try original.write("editor", at: url, backup: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRetargetedSymlinkIsRejectedEvenWithIdenticalContents() throws {
        let a = try write("a", "identical"), b = try write("b", "identical")
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        let baseline = try FileDocument.read(link)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: b)
        XCTAssertThrowsError(try baseline.write("edit", at: link, backup: true))
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "identical")
    }

    func testMissingFileCreationIsPrivateAndRejectsExternalCreation() throws {
        let url = directory.appendingPathComponent("new-file")
        let baseline = try FileDocument.read(url)
        XCTAssertNil(baseline.data)
        _ = try baseline.write("first", at: url, backup: true)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertThrowsError(try baseline.write("overwrite", at: url, backup: false))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first")
    }

    func testDanglingSymlinkCannotBeReplacedByNewFile() throws {
        let link = directory.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory.appendingPathComponent("absent"))
        XCTAssertThrowsError(try FileDocument.read(link))
        XCTAssertTrue(FileDocument.entryExists(link))
    }

    func testParentSymlinkRemainsIntact() throws {
        let actual = directory.appendingPathComponent("actual")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        let url = alias.appendingPathComponent("config")
        _ = try FileDocument.read(url).write("new", at: url, backup: false)
        XCTAssertEqual(try String(contentsOf: actual.appendingPathComponent("config"), encoding: .utf8), "new")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), actual.path)
    }
}
