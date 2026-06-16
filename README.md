# Konfig-Editor

Eine native macOS-App (SwiftUI) zum komfortablen Bearbeiten deiner Konfigurationsdateien:

- **Claude Code** – `~/.claude/settings.json` (+ lokaler Modus `~/.claude-local/settings.json`)
- **OpenCode** – `~/.config/opencode/opencode.json` (+ `tui.json`)
- **.zshrc** – `~/.zshrc`

## Features

- Sidebar mit allen Konfigurationsdateien (Icon, Status, „nicht vorhanden"-Hinweis)
- **Eigene Dateien hinzufügen** über den runden „+"-Button oben in der Seitenleiste (persistent gespeichert, per Rechtsklick wieder entfernbar)
- **Einfachklick** öffnet eine Datei
- Code-Editor mit **Syntax-Highlighting** für JSON, JSONC (JSON mit Kommentaren), Shell und YAML
- **Zeilennummern** und Monospace-Schrift
- **⌘/** kommentiert ausgewählte Zeilen ein/aus (`//` bzw. `#`, Cursor bleibt erhalten)
- **Suchen mit ⌘F** (native Find-Bar mit Treffer-Hervorhebung, inkrementell; ⌘G / ⌘⇧G springen zum nächsten/vorherigen Treffer)
- **Markieren kopiert sofort** in die Zwischenablage
- **Zoom** per ⌘+ / ⌘- / ⌘0 – Schriftgröße wird **über Neustarts gespeichert**
- **JSON-Validierung** live in der Statuszeile (versteht auch Kommentare & Trailing-Commas)
- **JSON formatieren** (Toolbar / hübsch einrücken)
- **Automatische Backups** beim Speichern (`datei.ext.<zeitstempel>.bak`, abschaltbar)
- **Im Finder anzeigen**, **Neu laden**, Warnung bei ungespeicherten Änderungen
- Dateiname & Pfad in der nativen Titelleiste, Fenster startet auf ~80 % der Bildschirmfläche

## Tastenkürzel

| Aktion                       | Kürzel |
|------------------------------|--------|
| Speichern                    | ⌘S     |
| Neu laden                    | ⌘R     |
| Zeilen ein-/auskommentieren  | ⌘/     |
| Suchen                       | ⌘F     |
| Nächster/voriger Treffer     | ⌘G / ⌘⇧G |
| Editor vergrößern            | ⌘+     |
| Editor verkleinern           | ⌘-     |
| Originalgröße                | ⌘0     |

## Bauen / Aktualisieren

```bash
cd ~/Projects/KonfigEditor
./build-app.sh                  # baut ~/Applications/Konfig-Editor.app
# optional Zielordner angeben:
./build-app.sh /Applications
```

Das Skript baut ein Release-Binary, erzeugt das App-Icon, packt ein `.app`-Bundle
und signiert es ad-hoc, damit Gatekeeper die lokale App startet.

## Neue Datei hinzufügen

In `Sources/KonfigEditor/ConfigFile.swift` die Liste `ConfigFile.known` erweitern
(Pfad, Anzeigename, Sprache, SF-Symbol) und neu bauen.

## Aufbau

| Datei | Zweck |
|-------|-------|
| `KonfigEditorApp.swift` | App-Einstieg, Menü, Startgröße |
| `ContentView.swift` | Split-View + Sidebar |
| `DetailView.swift` | Editor-Bereich, Toolbar, Statuszeile |
| `CodeEditor.swift` | NSTextView-Wrapper (TextKit 1), Zoom, Auto-Kopieren |
| `CodeTextView.swift` | NSTextView-Subklasse: ⌘/-Kommentieren, ⌘F-Suche |
| `LineNumberRulerView.swift` | Zeilennummern-Lineal |
| `WindowAccessor.swift` | Startgröße (~80 %) übers NSWindow |
| `SyntaxHighlighter.swift` | Regex-Highlighting JSON/JSONC/Shell/YAML |
| `Store.swift` | Laden/Speichern/Backup/Validierung |
| `Theme.swift` | Farben (Hell/Dunkel) |
