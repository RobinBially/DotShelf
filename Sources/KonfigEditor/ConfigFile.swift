import Foundation

/// Die unterstützten Sprachen für das Syntax-Highlighting.
enum ConfigLanguage {
    case json    // striktes JSON
    case jsonc   // JSON mit Kommentaren (z. B. opencode.json)
    case shell   // .zshrc / Shell-Skripte
    case yaml    // YAML (z. B. config.yaml)

    var displayName: String {
        switch self {
        case .json:  return "JSON"
        case .jsonc: return "JSON (mit Kommentaren)"
        case .shell: return "Shell"
        case .yaml:  return "YAML"
        }
    }

    /// Ob für diese Sprache eine JSON-Validierung/Formatierung sinnvoll ist.
    var isJSONLike: Bool {
        self == .json || self == .jsonc
    }
}

/// Beschreibt eine bearbeitbare Konfigurationsdatei.
struct ConfigFile: Identifiable, Hashable {
    let id: String
    let displayName: String
    let subtitle: String
    var symbol: String          // SF Symbol Name
    let language: ConfigLanguage
    var rawPath: String         // ggf. mit ~ am Anfang
    var isCustom: Bool = false  // vom Nutzer hinzugefügt → entfernbar
    var colorHex: String? = nil // eigene Symbolfarbe (überschreibt Sprach-Akzent)

    /// Vollständig aufgelöster Dateipfad.
    var url: URL {
        let expanded = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Verkürzter, gut lesbarer Pfad (Home → ~).
    var prettyPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }

    // Hinweis: KEIN id-only-Equatable/Hashable mehr. Swift synthetisiert beides
    // über alle Felder, damit SwiftUI Symbol-/Farb-Änderungen erkennt und die
    // Sidebar neu zeichnet. Identität läuft separat überall explizit über `id`.

    /// Erzeugt einen Eintrag für eine vom Nutzer hinzugefügte Datei.
    static func custom(path: String) -> ConfigFile {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return ConfigFile(
            id: "custom:" + url.path,
            displayName: url.lastPathComponent,
            subtitle: "Eigene Datei",
            symbol: "doc.text",
            language: detectLanguage(for: url),
            rawPath: url.path,
            isCustom: true
        )
    }

    /// Kopie des Eintrags mit neuem Pfad (nach Umbenennen auf der Festplatte).
    /// Eigene Dateien leiten Name/Sprache neu ab; kuratierte Einträge behalten
    /// ihr Label und Symbol und aktualisieren nur den Pfad.
    func renamed(to newURL: URL) -> ConfigFile {
        if isCustom {
            var copy = ConfigFile.custom(path: newURL.path)
            copy.symbol = symbol          // Symbol & Farbe übernehmen
            copy.colorHex = colorHex
            return copy
        }
        var copy = self                   // kuratiert: id/Label/Symbol behalten
        copy.rawPath = newURL.path
        return copy
    }

    /// Kopie des Eintrags mit anderem Listen-Symbol (SF Symbol).
    func withSymbol(_ newSymbol: String) -> ConfigFile {
        var copy = self
        copy.symbol = newSymbol
        return copy
    }

    /// Bestimmt die Sprache anhand des Dateinamens/der Endung.
    static func detectLanguage(for url: URL) -> ConfigLanguage {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return .json
        case "jsonc", "json5":
            return .jsonc
        case "yaml", "yml":
            return .yaml
        case "sh", "bash", "zsh", "zshrc", "bashrc", "profile", "zprofile", "env":
            return .shell
        default:
            // Dotfiles wie .zshrc / .bashrc ohne echte Endung → Shell
            if name.hasPrefix(".") && (name.contains("rc") || name.contains("profile") || name.contains("env")) {
                return .shell
            }
            return .shell
        }
    }
}

extension ConfigFile {
    /// Die kuratierte Liste der bekannten Konfigurationsdateien.
    static let known: [ConfigFile] = [
        ConfigFile(
            id: "claude-settings",
            displayName: "Claude Code – Settings",
            subtitle: "Globale Einstellungen",
            symbol: "sparkles",
            language: .json,
            rawPath: "~/.claude/settings.json"
        ),
        ConfigFile(
            id: "claude-local-settings",
            displayName: "Claude Code – Lokaler Modus",
            subtitle: "Settings für claude-local",
            symbol: "sparkle",
            language: .json,
            rawPath: "~/.claude-local/settings.json"
        ),
        ConfigFile(
            id: "opencode",
            displayName: "OpenCode",
            subtitle: "Provider & Modelle",
            symbol: "chevron.left.forwardslash.chevron.right",
            language: .jsonc,
            rawPath: "~/.config/opencode/opencode.json"
        ),
        ConfigFile(
            id: "opencode-tui",
            displayName: "OpenCode – TUI",
            subtitle: "Terminal-Oberfläche",
            symbol: "macwindow",
            language: .jsonc,
            rawPath: "~/.config/opencode/tui.json"
        ),
        ConfigFile(
            id: "zshrc",
            displayName: ".zshrc",
            subtitle: "Aliase, Funktionen, PATH",
            symbol: "terminal",
            language: .shell,
            rawPath: "~/.zshrc"
        )
    ]
}
