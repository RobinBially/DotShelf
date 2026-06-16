import SwiftUI
import Foundation

/// Ergebnis einer JSON-Prüfung.
enum ValidationState: Equatable {
    case notApplicable
    case valid
    case invalid(String)
}

@MainActor
final class Store: ObservableObject {

    @Published var files: [ConfigFile] = ConfigFile.known
    @Published var selection: ConfigFile.ID?

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

    @Published var text: String = ""
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

    init() {
        removedKnownIDs = UserDefaults.standard.stringArray(forKey: removedKnownKey) ?? []
        knownPathOverrides =
            (UserDefaults.standard.dictionary(forKey: knownOverridesKey) as? [String: String]) ?? [:]
        symbolOverrides =
            (UserDefaults.standard.dictionary(forKey: symbolOverridesKey) as? [String: String]) ?? [:]
        colorOverrides =
            (UserDefaults.standard.dictionary(forKey: colorOverridesKey) as? [String: String]) ?? [:]

        files = (ConfigFile.known
            .filter { !removedKnownIDs.contains($0.id) }
            .map { applyKnownOverride($0) }
            + loadCustomFiles())
            .map { applySymbolOverride($0) }
            .map { applyColorOverride($0) }

        if let first = files.first(where: { $0.exists }) ?? files.first {
            selection = first.id
            load(first)
        }
    }

    // MARK: - Zoom

    func zoomIn()  { fontSize = min(Self.maxFontSize, (fontSize + 1).rounded()) }
    func zoomOut() { fontSize = max(Self.minFontSize, (fontSize - 1).rounded()) }
    func resetZoom() { fontSize = 13 }

    // MARK: - Eigene Dateien

    private func loadCustomFiles() -> [ConfigFile] {
        let paths = UserDefaults.standard.stringArray(forKey: customFilesKey) ?? []
        return paths.map { ConfigFile.custom(path: $0) }
    }

    private func persistCustomFiles() {
        let paths = files.filter { $0.isCustom }.map { $0.url.path }
        UserDefaults.standard.set(paths, forKey: customFilesKey)
    }

    private func persistRemovedKnown() {
        UserDefaults.standard.set(removedKnownIDs, forKey: removedKnownKey)
    }

    private func persistKnownOverrides() {
        UserDefaults.standard.set(knownPathOverrides, forKey: knownOverridesKey)
    }

    private func persistSymbolOverrides() {
        UserDefaults.standard.set(symbolOverrides, forKey: symbolOverridesKey)
    }

    private func persistColorOverrides() {
        UserDefaults.standard.set(colorOverrides, forKey: colorOverridesKey)
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
        if let existing = files.first(where: { $0.id == new.id }) {
            select(existing)
            return
        }
        // Gespeicherte Symbol-/Farb-Overrides anwenden – wie beim Start (init).
        files.append(applyColorOverride(applySymbolOverride(new)))
        persistCustomFiles()
        select(new)
    }

    /// Erzeugt eine leere Datei auf der Festplatte und fügt sie sofort zur
    /// Seitenleiste hinzu. Kein Dialog – Standardname, später umbenennbar.
    func createEmptyFile() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
        let base = "leere-datei"
        let ext = "txt"
        var name = "\(base).\(ext)"
        var n = 1
        while files.contains(where: { $0.url.lastPathComponent == name })
            || FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "\(base)-\(n).\(ext)"
            n += 1
        }
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let new = ConfigFile.custom(path: url.path)
        files.append(applyColorOverride(applySymbolOverride(new)))
        persistCustomFiles()
        select(new)
        statusMessage = "Leere Datei erstellt – Name per Rechtsklick änderbar."
    }

    /// Legt mit einem Klick einen neuen, noch nicht gespeicherten Eintrag an.
    /// Name und Typ kann der Nutzer danach per Umbenennen anpassen; „Speichern"
    /// schreibt die Datei dann auf die Festplatte.
    func createFile() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
        let base = "neue-konfiguration"
        let ext = "json"
        var name = "\(base).\(ext)"
        var n = 1
        while files.contains(where: { $0.url.lastPathComponent == name })
            || FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "\(base)-\(n).\(ext)"
            n += 1
        }
        let new = ConfigFile.custom(path: dir.appendingPathComponent(name).path)
        files.append(new)
        persistCustomFiles()
        select(new)
        statusMessage = "Neuer Eintrag – Name/Typ per Rechtsklick änderbar, „Speichern“ legt die Datei an."
    }

    /// Entfernt einen Eintrag aus der Liste (Datei auf dem Datenträger bleibt).
    /// Funktioniert für eigene wie kuratierte Einträge; bei kuratierten wird
    /// das Ausblenden dauerhaft gemerkt.
    func removeFile(_ file: ConfigFile) {
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
        if selection == file.id {
            if let first = files.first {
                select(first)
            } else {
                selection = nil
                text = ""; originalText = ""
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

        if fm.fileExists(atPath: file.url.path) {
            guard !fm.fileExists(atPath: newURL.path) else {
                lastError = "Umbenennen fehlgeschlagen: „\(trimmed)“ existiert bereits."
                return
            }
            do {
                try fm.moveItem(at: file.url, to: newURL)
            } catch {
                lastError = "Umbenennen fehlgeschlagen: \(error.localizedDescription)"
                return
            }
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

        // Auswahl ggf. auf die neue id nachziehen.
        if selection == file.id { selection = renamed.id }
        statusMessage = "Umbenannt → \(trimmed)"
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
        guard let newID, newID != selection,
              let target = files.first(where: { $0.id == newID }) else { return }

        if hasUnsavedChanges, let current = selectedFile {
            let alert = NSAlert()
            alert.messageText = "Ungespeicherte Änderungen"
            alert.informativeText = "In „\(current.displayName)“ gibt es ungespeicherte Änderungen. Trotzdem wechseln?"
            alert.addButton(withTitle: "Speichern & wechseln")
            alert.addButton(withTitle: "Verwerfen & wechseln")
            alert.addButton(withTitle: "Abbrechen")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                save()
                select(target)
            case .alertSecondButtonReturn:
                select(target)
            default:
                // Abbrechen: Auswahl auf die aktuelle Datei zurücksetzen
                objectWillChange.send()
            }
        } else {
            select(target)
        }
    }

    var selectedFile: ConfigFile? {
        files.first { $0.id == selection }
    }

    var hasUnsavedChanges: Bool {
        text != originalText
    }

    // MARK: - Laden

    func select(_ file: ConfigFile) {
        guard file.id != selection else { return }
        selection = file.id
        load(file)
    }

    func load(_ file: ConfigFile) {
        lastError = nil
        if file.exists {
            do {
                let content = try String(contentsOf: file.url, encoding: .utf8)
                text = content
                originalText = content
                statusMessage = "Geladen · \(modifiedString(file))"
            } catch {
                text = ""
                originalText = ""
                lastError = "Konnte nicht lesen: \(error.localizedDescription)"
            }
        } else {
            text = ""
            originalText = ""
            statusMessage = "Datei existiert noch nicht – Speichern legt sie an."
        }
        revalidate()
    }

    func reload() {
        guard let file = selectedFile else { return }
        load(file)
    }

    // MARK: - Speichern

    func save() {
        guard let file = selectedFile else { return }
        lastError = nil

        // JSON vor dem Speichern prüfen, aber nicht hart blockieren.
        revalidate()

        do {
            let dir = file.url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            if autoBackup && file.exists {
                try makeBackup(of: file)
            }

            try text.write(to: file.url, atomically: true, encoding: .utf8)
            originalText = text
            objectWillChange.send()
            statusMessage = "Gespeichert ✓ · \(timestamp())"
        } catch {
            lastError = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func makeBackup(of file: ConfigFile) throws {
        let stamp = backupStamp()
        let backupURL = file.url.deletingPathExtension()
            .appendingPathExtension("\(file.url.pathExtension).\(stamp).bak")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.copyItem(at: file.url, to: backupURL)
    }

    // MARK: - JSON-Werkzeuge

    func revalidate() {
        guard let file = selectedFile, file.language.isJSONLike else {
            validation = .notApplicable
            return
        }
        let stripped = stripJSONComments(text)
        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validation = .valid
            return
        }
        guard let data = stripped.data(using: .utf8) else {
            validation = .invalid("Ungültige Textkodierung")
            return
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            validation = .valid
        } catch {
            validation = .invalid(jsonErrorMessage(error))
        }
    }

    /// Formatiert JSON hübsch (für reines JSON; JSONC verliert dabei Kommentare,
    /// daher dort nur mit Hinweis erlaubt).
    func formatJSON() {
        guard let file = selectedFile, file.language.isJSONLike else { return }
        let source = file.language == .jsonc ? stripJSONComments(text) : text
        guard let data = source.data(using: .utf8) else {
            lastError = "Formatieren fehlgeschlagen: ungültige Kodierung"
            return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            if let s = String(data: pretty, encoding: .utf8) {
                text = s
                statusMessage = file.language == .jsonc
                    ? "Formatiert (Kommentare entfernt)"
                    : "Formatiert ✓"
                revalidate()
            }
        } catch {
            lastError = "Formatieren fehlgeschlagen: \(jsonErrorMessage(error))"
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

    // MARK: - Hilfsfunktionen

    private func stripJSONComments(_ s: String) -> String {
        // Entfernt // und /* */ Kommentare, respektiert Strings.
        var result = ""
        result.reserveCapacity(s.count)
        var inString = false
        var escaped = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let next = s.index(after: i)
            if inString {
                result.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i = next
                continue
            }
            if c == "\"" {
                inString = true
                result.append(c)
                i = next
                continue
            }
            if c == "/", next < s.endIndex, s[next] == "/" {
                // bis Zeilenende überspringen
                while i < s.endIndex && s[i] != "\n" { i = s.index(after: i) }
                continue
            }
            if c == "/", next < s.endIndex, s[next] == "*" {
                i = s.index(i, offsetBy: 2)
                while i < s.endIndex {
                    if s[i] == "*", s.index(after: i) < s.endIndex,
                       s[s.index(after: i)] == "/" {
                        i = s.index(i, offsetBy: 2)
                        break
                    }
                    i = s.index(after: i)
                }
                continue
            }
            result.append(c)
            i = next
        }
        // Trailing-Kommas entfernen (häufig in JSONC), damit JSONSerialization nicht meckert.
        return removeTrailingCommas(result)
    }

    private func removeTrailingCommas(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: ",\\s*([}\\]])") else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
    }

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

    private func backupStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    func modifiedString(_ file: ConfigFile) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path),
              let date = attrs[.modificationDate] as? Date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return "geändert " + f.string(from: date)
    }
}
