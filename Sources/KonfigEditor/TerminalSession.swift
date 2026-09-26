import Foundation
import AppKit

/// Ein auszuführender Befehl – wie eine Run-Konfiguration in IntelliJ.
struct RunConfiguration: Identifiable, Hashable {
    /// Woher der Lauf stammt – steuert Formulierungen und Symbole.
    enum Kind: Hashable {
        case script
        case compose
        case shell
        case command
    }

    var id = UUID()
    var name: String
    var command: String
    var workingDirectory: URL
    /// Datei, aus der der Vorschlag stammt (Kontextmenü und Toolbar).
    var sourceFileID: ConfigFile.ID?
    var kind: Kind = .command

    /// Vorschlag passend zur Datei: Shell-Skripte werden ausgeführt,
    /// Docker-Compose-Dateien als Stack gestartet.
    static func suggestion(for file: ConfigFile) -> RunConfiguration {
        let directory = file.url.deletingLastPathComponent()
        if isComposeFile(file) {
            return RunConfiguration(
                name: "docker compose",
                command: "docker compose -f " + shellQuoted(file.url.path) + " up",
                workingDirectory: directory,
                sourceFileID: file.id,
                kind: .compose)
        }
        if isScriptFile(file) {
            let executable = FileManager.default.isExecutableFile(atPath: file.url.path)
            let command = executable
                ? shellQuoted(file.url.path)
                : "zsh " + shellQuoted(file.url.path)
            return RunConfiguration(name: file.displayName, command: command,
                                    workingDirectory: directory, sourceFileID: file.id,
                                    kind: .script)
        }
        // Für andere Dateien ist der Befehl frei: der Name entsteht dann später
        // aus dem Befehl selbst.
        return RunConfiguration(name: "", command: "",
                                workingDirectory: directory, sourceFileID: file.id)
    }

    /// Ob sich die Datei sinnvoll als Skript starten lässt: passende Endung
    /// oder Shebang-Zeile. Dotfiles wie .zshrc sind Konfiguration, kein Skript.
    static func isScriptFile(_ file: ConfigFile) -> Bool {
        isScriptFile(at: file.url)
    }

    static func isScriptFile(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["sh", "bash", "zsh", "ksh", "command"].contains(ext) { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 2) else { return false }
        return head == Data([0x23, 0x21])
    }

    static func isComposeFile(_ file: ConfigFile) -> Bool {
        isComposeFile(at: file.url)
    }

    static func isComposeFile(at url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return ["docker-compose.yml", "docker-compose.yaml",
                "compose.yml", "compose.yaml"].contains(name)
    }

    /// Setzt einen Pfad so in Anführungszeichen, wie es die Shell erwartet.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Ein Skript-Lauf. Erscheint als temporärer Eintrag in der Seitenleiste und
/// wird im Editor als Terminal angezeigt.
@MainActor
final class TerminalSession: ObservableObject, Identifiable {

    enum Status: Equatable {
        case running
        case exited(code: Int32, stopped: Bool)
        case signaled(signal: Int32, stopped: Bool)
        case failed(String)
    }

    let id = UUID()
    let title: String
    let command: String
    let workingDirectory: URL
    let sourceFileID: ConfigFile.ID?
    let kind: RunConfiguration.Kind
    let buffer: TerminalBuffer

    @Published private(set) var status: Status = .running
    @Published private(set) var outputVersion = 0
    @Published private(set) var isStopping = false
    /// Ob hier wirklich etwas arbeitet: Ein Skript tut das, solange es läuft.
    /// Eine Shell steht dagegen an der Eingabeaufforderung und ist erst dann
    /// beschäftigt, wenn ein Befehl darin läuft.
    @Published private(set) var isBusy = false
    private(set) var startedAt = Date()
    private(set) var finishedAt: Date?

    private let runner = ScriptRunner()
    private let environment: [String: String]
    private var pending = Data()
    private var flushScheduled = false
    private var busyTimer: Timer?

    init(configuration: RunConfiguration, columns: Int = TerminalBuffer.defaultColumns,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        let command = configuration.command
        title = configuration.name.isEmpty
            ? Self.defaultTitle(for: command)
            : configuration.name
        self.command = command
        workingDirectory = configuration.workingDirectory
        sourceFileID = configuration.sourceFileID
        kind = configuration.kind
        self.environment = environment
        buffer = TerminalBuffer(columns: columns)
        installCallbacks()
    }

    // MARK: - Zustand

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    /// Ob der Lauf als Fehler gilt (Abbruch durch den Nutzer zählt nicht).
    var hasFailed: Bool {
        switch status {
        case .running: return false
        case .exited(let code, let stopped): return !stopped && code != 0
        case .signaled(_, let stopped): return !stopped
        case .failed: return true
        }
    }

    var statusText: String {
        switch status {
        case .running:
            if isStopping { return L10n.text("Stopping…") }
            return isBusy ? L10n.text("Running…") : L10n.text("Ready")
        case .exited(let code, let stopped):
            if stopped { return L10n.text("Stopped") }
            return code == 0 ? L10n.text("Finished") : L10n.format("Exited with code %d", code)
        case .signaled(let signal, let stopped):
            if stopped { return L10n.text("Stopped") }
            return L10n.format("Ended by signal %d", signal)
        case .failed(let message):
            return message
        }
    }

    var durationText: String {
        let end = finishedAt ?? Date()
        let seconds = max(0, end.timeIntervalSince(startedAt))
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    var prettyWorkingDirectory: String {
        (workingDirectory.path as NSString).abbreviatingWithTildeInPath
    }

    var plainText: String { buffer.plainText }

    // MARK: - Steuerung

    func start(rows: Int = 30) {
        startedAt = Date()
        finishedAt = nil
        isStopping = false
        status = .running
        echoCommand()
        do {
            try runner.start(command: command, workingDirectory: workingDirectory,
                             columns: buffer.columns, rows: rows, environment: environment)
            startBusyUpdates()
        } catch {
            status = .failed(error.localizedDescription)
            finishedAt = Date()
            outputVersion = buffer.version
            stopBusyUpdates()
        }
    }

    // MARK: - Beschäftigt oder wartend

    /// Eine Shell wechselt zwischen Warten und Arbeiten. Der Blick auf die
    /// Kindprozesse verrät, was gerade gilt – ein Rädchen soll nur laufen,
    /// wenn wirklich etwas arbeitet.
    private func startBusyUpdates() {
        stopBusyUpdates()
        updateBusy()
        guard kind == .shell else { return }
        busyTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBusy() }
        }
    }

    private func stopBusyUpdates() {
        busyTimer?.invalidate()
        busyTimer = nil
        if isBusy { isBusy = false }
    }

    private func updateBusy() {
        guard isRunning else { return }
        let busy = kind == .shell ? runner.hasRunningChildren : true
        if busy != isBusy { isBusy = busy }
    }

    /// Startet denselben Befehl erneut; die Ausgabe von vorher wird verworfen.
    func rerun(rows: Int = 30) {
        guard !isRunning else { return }
        pending = Data()
        buffer.clear()
        outputVersion = buffer.version
        start(rows: rows)
    }

    func stop() {
        guard isRunning else { return }
        isStopping = true
        runner.stop()
    }

    func clearOutput() {
        buffer.clear()
        outputVersion = buffer.version
    }

    func send(_ data: Data) {
        guard isRunning else { return }
        runner.send(data)
    }

    func resize(columns: Int, rows: Int) {
        buffer.resize(columns: columns)
        runner.resize(columns: buffer.columns, rows: rows)
    }

    // MARK: - Ausgabe

    /// Zeigt den ausgeführten Befehl als erste Zeile des Terminals.
    private func echoCommand() {
        let command = self.command.isEmpty ? L10n.text("Shell") : self.command
        // Wagenrücklauf nicht vergessen: ein reiner Zeilenumbruch würde die
        // Spalte stehen lassen und die folgende Ausgabe einrücken.
        buffer.feed(Data("\u{1B}[38;5;8m$ \(command)\u{1B}[0m\r\n".utf8))
        outputVersion = buffer.version
    }

    private func installCallbacks() {
        runner.onOutput = { [weak self] data in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(data) }
            }
        }
        runner.onExit = { [weak self] termination in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.complete(termination) }
            }
        }
    }

    private func receive(_ data: Data) {
        pending.append(data)
        guard !flushScheduled else { return }
        flushScheduled = true
        // Ausgabe bündeln: ein Terminal darf schneller schreiben, als
        // SwiftUI neu zeichnen muss.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let data = pending
        pending = Data()
        buffer.feed(data)
        outputVersion = buffer.version
    }

    private func complete(_ termination: ScriptRunner.Termination) {
        flush()
        finishedAt = Date()
        isStopping = false
        stopBusyUpdates()
        let stopped = runner.stoppedByUser
        switch termination {
        case .exited(let code):
            status = .exited(code: code, stopped: stopped)
        case .signaled(let signal):
            status = .signaled(signal: signal, stopped: stopped)
        }
    }

    private static func defaultTitle(for command: String) -> String {
        let first = command.split(separator: " ").first.map(String.init) ?? ""
        let name = (first as NSString).lastPathComponent
        return name.isEmpty ? L10n.text("Terminal") : name
    }
}
