import SwiftUI
import Foundation

/// Ergebnis einer JSON-Prüfung.
enum ValidationState: Equatable {
    case notApplicable
    case valid
    case invalid(String)
}

/// Was der Editor gerade zeigt: eine Konfigurationsdatei oder ein Terminal.
enum ShelfSelection: Hashable {
    case file(ConfigFile.ID)
    case terminal(UUID)

    var fileID: ConfigFile.ID? {
        if case .file(let id) = self { return id }
        return nil
    }

    var terminalID: UUID? {
        if case .terminal(let id) = self { return id }
        return nil
    }
}

@MainActor
final class Store: ObservableObject {

    @Published var files: [ConfigFile] = ConfigFile.known
    @Published var selection: ShelfSelection?

    /// Temporäre Einträge der Seitenleiste: laufende und beendete Skript-Läufe.
    @Published var sessions: [TerminalSession] = []

    /// Offener Run-Dialog (nil = zu).
    @Published var runDraft: RunConfiguration?

    /// Seitenleiste eingeklappt → nur Symbole, Dateien bleiben erreichbar.
    @Published var sidebarCollapsed: Bool = false
    @Published var splitVisibility: NavigationSplitViewVisibility = .all

    func setSidebarCollapsed(_ collapsed: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            sidebarCollapsed = collapsed
        }
    }

    /// Eintrag, dessen Symbol gerade im Picker-Sheet bearbeitet wird (nil = zu).
    @Published var symbolPickerTarget: ConfigFile?

    /// Farbpalette für den Symbol-Picker (Hex, Apple-Systemfarben).
    static let colorChoices = [
        "FF9F0A", "FF453A", "FF375F", "BF5AF2", "5E5CE6",
        "0A84FF", "64D2FF", "30D158", "FFD60A", "AC8E68", "8E8E93"
    ]

    /// Auswahl an SF-Symbolen für den Symbol-Picker.
    static let symbolChoices = [
        "doc.text", "doc.plaintext", "doc.richtext", "doc.badge.gearshape",
        "gearshape", "gearshape.2", "slider.horizontal.3",
        "terminal", "chevron.left.forwardslash.chevron.right",
        "curlybraces", "curlybraces.square", "macwindow",
        "list.bullet", "list.bullet.rectangle",
        "key", "key.fill", "lock", "lock.shield",
        "globe", "network", "cloud", "server.rack",
        "flame", "leaf", "star", "bolt", "sparkles", "sparkle",
        "cube", "shippingbox", "folder", "tray", "archivebox",
        "wrench.and.screwdriver", "hammer", "paintbrush",
        "cpu", "memorychip", "gauge", "tag", "bookmark", "flag", "bell", "envelope"
    ]

    @Published var text: String = "" { didSet { revalidate() } }
    @Published var originalText: String = ""
    @Published var validation: ValidationState = .notApplicable
    @Published var statusMessage: String = ""
    @Published var lastError: String?

    /// Backups beim Speichern automatisch anlegen.
    @AppStorage("autoBackup") var autoBackup: Bool = true

    /// Editor-Schriftgröße (Zoom) – über Neustarts hinweg gespeichert.
    @AppStorage("editorFontSize") var fontSize: Double = 13

    static let minFontSize: Double = 9
    static let maxFontSize: Double = 28

    private let customFilesKey = "customFilePaths"
    private let removedKnownKey = "removedKnownIDs"
    private let knownOverridesKey = "knownPathOverrides"
    private let symbolOverridesKey = "symbolOverrides"
    private let colorOverridesKey = "colorOverrides"

    /// Vom Nutzer entfernte kuratierte Einträge (per id).
    private var removedKnownIDs: [String] = []
    /// Pfad-Überschreibungen kuratierter Einträge nach Umbenennen (id → Pfad).
    private var knownPathOverrides: [String: String] = [:]
    /// Selbst gewählte Listen-Symbole (id → SF-Symbol-Name).
    private var symbolOverrides: [String: String] = [:]
    /// Selbst gewählte Symbolfarben (id → Hex).
    private var colorOverrides: [String: String] = [:]

    enum PendingChangesDecision { case save, discard, cancel }

    private let defaults: UserDefaults
    private let newFileDirectory: URL
    private let pendingChangesDecision: ((ConfigFile) -> PendingChangesDecision)?
    private let confirmCommentRemoval: (() -> Bool)?
    private let confirmStopRunning: (() -> Bool)?
    private var diskBaseline: FileDocument?
    /// Datei, zu der der Editor-Puffer gehört. Bleibt bestehen, während ein
    /// Terminal angezeigt wird – so gehen ungespeicherte Änderungen nicht verloren.
    private(set) var openFile: ConfigFile?

    init(initialFiles: [ConfigFile]? = nil, defaults: UserDefaults = .standard,
         newFileDirectory: URL? = nil,
         pendingChangesDecision: ((ConfigFile) -> PendingChangesDecision)? = nil,
         confirmCommentRemoval: (() -> Bool)? = nil,
         confirmStopRunning: (() -> Bool)? = nil) {
        self.defaults = defaults
        self.newFileDirectory = newFileDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.pendingChangesDecision = pendingChangesDecision
        self.confirmCommentRemoval = confirmCommentRemoval
        self.confirmStopRunning = confirmStopRunning
        _autoBackup = AppStorage(wrappedValue: true, "autoBackup", store: defaults)
        _fontSize = AppStorage(wrappedValue: 13, "editorFontSize", store: defaults)
        removedKnownIDs = defaults.stringArray(forKey: removedKnownKey) ?? []
        knownPathOverrides =
            (defaults.dictionary(forKey: knownOverridesKey) as? [String: String]) ?? [:]
        symbolOverrides =
            (defaults.dictionary(forKey: symbolOverridesKey) as? [String: String]) ?? [:]
        colorOverrides =
            (defaults.dictionary(forKey: colorOverridesKey) as? [String: String]) ?? [:]

        files = ((initialFiles ?? ConfigFile.known)
            .filter { !removedKnownIDs.contains($0.id) }
            .map { applyKnownOverride($0) }
            + (initialFiles == nil ? loadCustomFiles() : []))
            .map { applySymbolOverride($0) }
            .map { applyColorOverride($0) }

        if let first = files.first(where: { $0.exists }) ?? files.first {
            selection = .file(first.id)
            load(first)
        }
    }

    // MARK: - Zoom

    func zoomIn()  { fontSize = min(Self.maxFontSize, (fontSize + 1).rounded()) }
    func zoomOut() { fontSize = max(Self.minFontSize, (fontSize - 1).rounded()) }
    func resetZoom() { fontSize = 13 }

    // MARK: - Eigene Dateien

    private func loadCustomFiles() -> [ConfigFile] {
        let paths = defaults.stringArray(forKey: customFilesKey) ?? []
        return paths.map { ConfigFile.custom(path: $0) }
    }

    private func persistCustomFiles() {
        let paths = files.filter { $0.isCustom }.map { $0.url.path }
        defaults.set(paths, forKey: customFilesKey)
    }

    private func persistRemovedKnown() {
        defaults.set(removedKnownIDs, forKey: removedKnownKey)
    }

    private func persistKnownOverrides() {
        defaults.set(knownPathOverrides, forKey: knownOverridesKey)
    }

    private func persistSymbolOverrides() {
        defaults.set(symbolOverrides, forKey: symbolOverridesKey)
    }

    private func persistColorOverrides() {
        defaults.set(colorOverrides, forKey: colorOverridesKey)
    }

    /// Verschiebt einen Override-Eintrag von einer id auf eine andere.
    private func migrateOverride(_ dict: inout [String: String], from old: String, to new: String) {
        guard let value = dict[old] else { return }
        dict[new] = value
        dict[old] = nil
    }

    /// Wendet eine gespeicherte Pfad-Überschreibung auf einen kuratierten Eintrag an.
    private func applyKnownOverride(_ file: ConfigFile) -> ConfigFile {
        guard let path = knownPathOverrides[file.id] else { return file }
        return file.renamed(to: URL(fileURLWithPath: path))
    }

    /// Wendet ein gespeichertes Listen-Symbol auf einen Eintrag an.
    private func applySymbolOverride(_ file: ConfigFile) -> ConfigFile {
        guard let symbol = symbolOverrides[file.id] else { return file }
        return file.withSymbol(symbol)
    }

    /// Wendet eine gespeicherte Symbolfarbe auf einen Eintrag an.
    private func applyColorOverride(_ file: ConfigFile) -> ConfigFile {
        guard let hex = colorOverrides[file.id] else { return file }
        var copy = file
        copy.colorHex = hex
        return copy
    }

    /// Fügt eine Datei hinzu und wählt sie aus (Duplikate werden nur ausgewählt).
    func addFile(url: URL) {
        let new = ConfigFile.custom(path: url.path)
        if let existing = files.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            select(existing)
            return
        }
        guard confirmPendingChanges() else { return }
        // Gespeicherte Symbol-/Farb-Overrides anwenden – wie beim Start (init).
        files.append(applyColorOverride(applySymbolOverride(new)))
        persistCustomFiles()
        activate(new)
    }

    /// Erzeugt eine leere Datei auf der Festplatte und fügt sie sofort zur
    /// Seitenleiste hinzu. Kein Dialog – Standardname, später umbenennbar.
    func createEmptyFile() {
        guard confirmPendingChanges() else { return }
        let dir = newFileDirectory
        let base = "untitled"
        let ext = "txt"
        var name = "\(base).\(ext)"
        var n = 1
        while files.contains(where: { $0.url.lastPathComponent == name })
            || FileDocument.entryExists(dir.appendingPathComponent(name)) {
            name = "\(base)-\(n).\(ext)"
            n += 1
        }
        let url = dir.appendingPathComponent(name)
        do {
            let baseline = try FileDocument.read(url)
            guard baseline.data == nil else { throw FileDocument.AccessError.conflict }
            _ = try baseline.write("", at: url, backup: false)
        } catch {
            lastError = L10n.format("Could not create file: %@", error.localizedDescription)
            return
        }
        let new = ConfigFile.custom(path: url.path)
        files.append(applyColorOverride(applySymbolOverride(new)))
        persistCustomFiles()
        activate(new)
        statusMessage = L10n.text("Empty file created. Right-click to rename it.")
    }

    /// Entfernt einen Eintrag aus der Liste (Datei auf dem Datenträger bleibt).
    /// Funktioniert für eigene wie kuratierte Einträge; bei kuratierten wird
    /// das Ausblenden dauerhaft gemerkt.
    func removeFile(_ file: ConfigFile) {
        if openFile?.id == file.id, !confirmPendingChanges() { return }
        files.removeAll { $0.id == file.id }
        // Symbol-/Farb-Overrides dieses Eintrags aufräumen – einheitlich für
        // kuratierte wie eigene Einträge.
        symbolOverrides[file.id] = nil
        colorOverrides[file.id] = nil
        persistSymbolOverrides()
        persistColorOverrides()
        if file.isCustom {
            persistCustomFiles()
        } else {
            if !removedKnownIDs.contains(file.id) { removedKnownIDs.append(file.id) }
            knownPathOverrides[file.id] = nil
            persistRemovedKnown()
            persistKnownOverrides()
        }
        if openFile?.id == file.id {
            openFile = nil
            diskBaseline = nil
            text = ""; originalText = ""
            validation = .notApplicable
        }
        if selection?.fileID == file.id {
            if let first = files.first {
                activate(first)
            } else if let session = sessions.first {
                selection = .terminal(session.id)
            } else {
                selection = nil
            }
        }
    }

    /// Benennt die Datei auf der Festplatte um (mv) und aktualisiert den Eintrag.
    /// `newName` ist der neue Dateiname (ohne Pfad).
    func renameFile(_ file: ConfigFile, to newName: String) {
        lastError = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"),
              trimmed != file.url.lastPathComponent else { return }

        let newURL = file.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        let fm = FileManager.default

        guard !FileDocument.entryExists(newURL) else {
            lastError = L10n.format("Could not rename: %@ already exists.", trimmed)
            return
        }
        guard FileDocument.entryExists(file.url) else {
            lastError = L10n.text("Could not rename: the source file no longer exists.")
            return
        }
        do {
            if openFile?.id == file.id {
                guard let diskBaseline else { throw FileDocument.AccessError.unreadable }
                try diskBaseline.checkUnchanged(at: file.url)
            }
            try fm.moveItem(at: file.url, to: newURL)
            if openFile?.id == file.id { diskBaseline = diskBaseline?.relocated(to: newURL) }
        } catch {
            lastError = L10n.format("Could not rename: %@", error.localizedDescription)
            return
        }

        let renamed = file.renamed(to: newURL)
        if let idx = files.firstIndex(where: { $0.id == file.id }) {
            files[idx] = renamed
        }

        if file.isCustom {
            persistCustomFiles()
            // id eigener Dateien ist pfadbasiert → Overrides auf neue id umziehen.
            if renamed.id != file.id {
                migrateOverride(&symbolOverrides, from: file.id, to: renamed.id)
                migrateOverride(&colorOverrides, from: file.id, to: renamed.id)
                persistSymbolOverrides()
                persistColorOverrides()
            }
        } else {
            knownPathOverrides[file.id] = newURL.path
            persistKnownOverrides()
        }

        // Puffer und Auswahl ggf. auf die neue id nachziehen.
        if openFile?.id == file.id { openFile = renamed }
        if selection?.fileID == file.id { selection = .file(renamed.id) }
        revalidate()
        statusMessage = L10n.format("Renamed to %@", trimmed)
    }

    // MARK: - Datei-Symbol

    /// Setzt das Listen-Symbol (SF Symbol) eines Eintrags und merkt es dauerhaft.
    func setSymbol(_ file: ConfigFile, to symbol: String) {
        guard let idx = files.firstIndex(where: { $0.id == file.id }) else { return }
        files[idx] = files[idx].withSymbol(symbol)
        symbolOverrides[file.id] = symbol
        persistSymbolOverrides()
    }

    /// Setzt die Symbolfarbe (Hex) eines Eintrags; `nil` = Sprach-Standardfarbe.
    func setColor(_ file: ConfigFile, to hex: String?) {
        guard let idx = files.firstIndex(where: { $0.id == file.id }) else { return }
        var copy = files[idx]
        copy.colorHex = hex
        files[idx] = copy
        colorOverrides[file.id] = hex
        persistColorOverrides()
    }

    /// Behandelt einen Auswahlwechsel (Einfachklick) inkl. Nachfrage bei
    /// ungespeicherten Änderungen der bisherigen Datei.
    func selectFromSidebar(_ newID: ConfigFile.ID?) {
        guard let newID, let target = files.first(where: { $0.id == newID }) else { return }
        select(target)
    }

    /// Shared by navigation, reload and the application close/quit lifecycle.
    func confirmPendingChanges() -> Bool {
        guard hasUnsavedChanges else { return true }
        guard let current = selectedFile else { return false }
        let decision: PendingChangesDecision
        if let pendingChangesDecision {
            decision = pendingChangesDecision(current)
        } else {
            let alert = NSAlert()
            alert.messageText = L10n.text("Unsaved changes")
            alert.informativeText = L10n.format("Save your changes to %@ before continuing?", current.displayName)
            alert.addButton(withTitle: L10n.text("Save"))
            alert.addButton(withTitle: L10n.text("Discard"))
            alert.addButton(withTitle: L10n.text("Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: decision = .save
            case .alertSecondButtonReturn: decision = .discard
            default: decision = .cancel
            }
        }
        switch decision {
        case .save: return save()
        case .discard: return true
        case .cancel: return false
        }
    }

    /// Die im Editor angezeigte Datei (nil, solange ein Terminal ausgewählt ist).
    var selectedFile: ConfigFile? {
        guard let id = selection?.fileID else { return nil }
        return files.first { $0.id == id }
    }

    /// Das ausgewählte Terminal (nil, solange eine Datei angezeigt wird).
    var selectedTerminal: TerminalSession? {
        guard let id = selection?.terminalID else { return nil }
        return sessions.first { $0.id == id }
    }

    var hasUnsavedChanges: Bool {
        text != originalText
    }

    // MARK: - Laden

    func select(_ file: ConfigFile) {
        // Dieselbe Datei: der Puffer bleibt erhalten, nur die Ansicht wechselt
        // zurück – etwa aus einem Terminal heraus.
        if openFile?.id == file.id {
            selection = .file(file.id)
            revalidate()
            return
        }
        guard confirmPendingChanges() else { return }
        activate(file)
    }

    private func activate(_ file: ConfigFile) {
        selection = .file(file.id)
        load(file)
    }

    private func load(_ file: ConfigFile) {
        openFile = file
        lastError = nil
        diskBaseline = nil
        do {
            let baseline = try FileDocument.read(file.url)
            let content: String
            if let data = baseline.data {
                guard let decoded = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                content = decoded
                statusMessage = L10n.format("Loaded · %@", modifiedString(file))
            } else {
                content = ""
                statusMessage = L10n.text("This file does not exist yet. Saving will create it.")
            }
            diskBaseline = baseline
            text = content
            originalText = content
        } catch {
            text = ""
            originalText = ""
            lastError = L10n.format("Could not read: %@", error.localizedDescription)
        }
        revalidate()
    }

    func reload() {
        guard let file = selectedFile, confirmPendingChanges() else { return }
        load(file)
    }

    // MARK: - Saving

    @discardableResult
    func save() -> Bool {
        guard let file = openFile else { return false }
        lastError = nil
        revalidate()
        do {
            guard let diskBaseline else { throw FileDocument.AccessError.unreadable }
            self.diskBaseline = try diskBaseline.write(text, at: file.url, backup: autoBackup)
            originalText = text
            statusMessage = L10n.format("Saved ✓ · %@", timestamp())
            objectWillChange.send()
            return true
        } catch {
            lastError = L10n.format("Could not save: %@", error.localizedDescription)
            return false
        }
    }

    // MARK: - JSON tools

    func revalidate() {
        guard let file = openFile, file.language.isJSONLike else {
            validation = .notApplicable
            return
        }
        do {
            _ = try JSONDocument.parse(text, allowsComments: file.language == .jsonc)
            validation = .valid
        } catch {
            validation = .invalid(jsonErrorMessage(error))
        }
    }

    func formatJSON() {
        guard let file = selectedFile, file.language.isJSONLike else { return }
        do {
            let parsed = try JSONDocument.parse(text, allowsComments: file.language == .jsonc)
            let formatted = try JSONDocument.formatted(parsed.object)
            if parsed.hasComments {
                let approved: Bool
                if let confirmCommentRemoval {
                    approved = confirmCommentRemoval()
                } else {
                    let alert = NSAlert()
                    alert.messageText = L10n.text("Remove comments while formatting?")
                    alert.informativeText = L10n.text("Formatting JSONC removes all comments. The file will only change on disk when you save.")
                    alert.addButton(withTitle: L10n.text("Format and remove comments"))
                    alert.addButton(withTitle: L10n.text("Cancel"))
                    approved = alert.runModal() == .alertFirstButtonReturn
                }
                guard approved else { return }
            }
            text = formatted
            lastError = nil
            statusMessage = parsed.hasComments ? L10n.text("Formatted (comments removed)") : L10n.text("Formatted ✓")
        } catch {
            lastError = L10n.format("Could not format: %@", jsonErrorMessage(error))
        }
    }

    func revealInFinder() {
        guard let file = selectedFile else { return }
        if file.exists {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([file.url.deletingLastPathComponent()])
        }
    }

    // MARK: - Skripte ausführen

    /// Vorschlag für eine Datei: Shell-Skript oder Docker-Compose-Stack.
    func suggestedRunConfiguration(for file: ConfigFile?) -> RunConfiguration {
        guard let file else {
            return RunConfiguration(
                name: "",
                command: "",
                workingDirectory: preferredWorkingDirectory)
        }
        return RunConfiguration.suggestion(for: file)
    }

    /// Arbeitsverzeichnis neuer Läufe: neben der bearbeiteten Datei, sonst wie
    /// beim letzten Lauf, sonst das Home-Verzeichnis.
    private var preferredWorkingDirectory: URL {
        if let open = openFile { return open.url.deletingLastPathComponent() }
        if let last = sessions.first { return last.workingDirectory }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Öffnet den Run-Dialog, vorbelegt für die angegebene Datei.
    func presentRunSheet(for file: ConfigFile?) {
        runDraft = suggestedRunConfiguration(for: file)
    }

    /// Öffnet den Run-Dialog für eine frei eingegebene Befehlszeile.
    func presentRunSheetWithoutSuggestion() {
        presentRunSheet(for: nil)
    }

    /// Führt den erkannten Befehl einer Datei sofort aus – ohne Dialog, wie der
    /// grüne Pfeil in IntelliJ. Gibt es nichts zu erkennen (etwa eine Markdown-
    /// Datei), öffnet sich der Dialog, weil der Befehl dann frei ist.
    @discardableResult
    func runSuggestion(for file: ConfigFile?) -> TerminalSession? {
        guard let file else {
            presentRunSheetWithoutSuggestion()
            return nil
        }
        let suggestion = RunConfiguration.suggestion(for: file)
        guard !suggestion.command.isEmpty else {
            presentRunSheet(for: file)
            return nil
        }
        return run(suggestion)
    }

    /// ⌃R: Steht ein Terminal im Vordergrund, läuft dessen Befehl erneut,
    /// sonst startet der Vorschlag der bearbeiteten Datei.
    @discardableResult
    func runSelectedFile() -> TerminalSession? {
        if let terminal = selectedTerminal {
            terminal.rerun()
            return terminal
        }
        return runSuggestion(for: selectedFile)
    }

    /// Öffnet ein freies Terminal: eine interaktive Login-Shell zum Arbeiten
    /// im Ordner – Eingabe, Strg-C und Einfügen verhalten sich wie gewohnt.
    @discardableResult
    func openTerminal(in directory: URL? = nil) -> TerminalSession? {
        let configuration = RunConfiguration(
            name: L10n.text("Shell"),
            command: "exec /bin/zsh -l -i",
            workingDirectory: directory ?? preferredWorkingDirectory,
            kind: .shell)
        return run(configuration)
    }

    /// Legt einen temporären Terminal-Eintrag an und führt den Befehl aus.
    @discardableResult
    func run(_ configuration: RunConfiguration) -> TerminalSession? {
        let command = configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        var configuration = configuration
        configuration.command = command

        // Vor dem Start speichern, wenn genau diese Datei gerade bearbeitet wird.
        if let id = configuration.sourceFileID, openFile?.id == id, hasUnsavedChanges {
            guard save() else { return nil }
        }

        let session = TerminalSession(configuration: configuration)
        sessions.insert(session, at: 0)
        selection = .terminal(session.id)
        session.start()
        return session
    }

    func selectTerminal(_ session: TerminalSession) {
        selection = .terminal(session.id)
    }

    func stopSelectedSession() {
        selectedTerminal?.stop()
    }

    func rerunSelectedSession() {
        selectedTerminal?.rerun()
    }

    func clearSelectedSession() {
        selectedTerminal?.clearOutput()
    }

    /// Schließt einen Terminal-Eintrag. Arbeitet darin noch etwas, wird vorher
    /// gefragt; ein Terminal, das nur an der Eingabeaufforderung steht, geht
    /// ohne Rückfrage zu.
    func closeSession(_ session: TerminalSession) {
        if session.isBusy {
            let approved: Bool
            if let confirmStopRunning {
                approved = confirmStopRunning()
            } else {
                let alert = NSAlert()
                if session.kind == .shell {
                    alert.messageText = L10n.text("Close the terminal?")
                    alert.informativeText = L10n.text(
                        "A command is still running in this terminal. Closing the entry ends it.")
                    alert.addButton(withTitle: L10n.text("Close"))
                } else {
                    alert.messageText = L10n.text("Stop the running script?")
                    alert.informativeText = L10n.format(
                        "“%@” is still running. Closing the terminal stops it.", session.title)
                    alert.addButton(withTitle: L10n.text("Stop and close"))
                }
                alert.addButton(withTitle: L10n.text("Cancel"))
                approved = alert.runModal() == .alertFirstButtonReturn
            }
            guard approved else { return }
        }
        session.stop()
        sessions.removeAll { $0.id == session.id }
        guard selection?.terminalID == session.id else { return }
        if let open = openFile {
            selection = .file(open.id)
        } else if let first = files.first {
            activate(first)
        } else if let next = sessions.first {
            selection = .terminal(next.id)
        } else {
            selection = nil
        }
    }

    /// Beendet alle laufenden Skripte (etwa beim Schließen der App).
    func stopAllSessions() {
        for session in sessions where session.isRunning {
            session.stop()
        }
    }

    // MARK: - Hilfsfunktionen

    private func jsonErrorMessage(_ error: Error) -> String {
        let ns = error as NSError
        if let debug = ns.userInfo[NSDebugDescriptionErrorKey] as? String {
            return debug
        }
        return ns.localizedDescription
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    func modifiedString(_ file: ConfigFile) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path),
              let date = attrs[.modificationDate] as? Date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return L10n.format("modified %@", f.string(from: date))
    }
}
