import AppKit

/// Regex-basiertes Syntax-Highlighting für JSON(C) und Shell.
/// Klein gehalten und auf typische Config-Dateien zugeschnitten.
struct SyntaxHighlighter {

    let font: NSFont

    init(font: NSFont) {
        self.font = font
    }

    func highlight(_ storage: NSTextStorage, language: ConfigLanguage) {
        let fullRange = NSRange(location: 0, length: storage.length)
        let text = storage.string

        storage.beginEditing()
        // Basis: alles zurücksetzen
        storage.setAttributes([
            .font: font,
            .foregroundColor: SyntaxTheme.foreground
        ], range: fullRange)

        switch language {
        case .json:  applyJSON(to: storage, text: text, allowComments: false)
        case .jsonc: applyJSON(to: storage, text: text, allowComments: true)
        case .shell: applyShell(to: storage, text: text)
        case .yaml:  applyYAML(to: storage, text: text)
        }
        storage.endEditing()
    }

    // MARK: - Helpers

    private func apply(_ color: NSColor, regex pattern: String, to storage: NSTextStorage,
                       text: String, group: Int = 0,
                       options: NSRegularExpression.Options = []) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(text.startIndex..., in: text)
        re.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > group else { return }
            let r = match.range(at: group)
            if r.location != NSNotFound && r.length > 0 {
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
    }

    // MARK: - JSON / JSONC

    private func applyJSON(to storage: NSTextStorage, text: String, allowComments: Bool) {
        // Interpunktion
        apply(SyntaxTheme.punctuation, regex: "[\\{\\}\\[\\]:,]", to: storage, text: text)
        // Zahlen
        apply(SyntaxTheme.number, regex: "(?<![\\w\"])-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?",
              to: storage, text: text)
        // true / false / null
        apply(SyntaxTheme.constant, regex: "\\b(?:true|false|null)\\b", to: storage, text: text)
        // Strings (mit Escapes); Gruppe 0 = ganzer String
        apply(SyntaxTheme.string, regex: "\"(?:[^\"\\\\]|\\\\.)*\"", to: storage, text: text)
        // Schlüssel: String unmittelbar vor einem Doppelpunkt → Gruppe 1
        apply(SyntaxTheme.key, regex: "(\"(?:[^\"\\\\]|\\\\.)*\")\\s*:",
              to: storage, text: text, group: 1)
        // Kommentare zuletzt, damit sie auskommentierte Strings überschreiben
        if allowComments {
            apply(SyntaxTheme.comment, regex: "//[^\\n]*", to: storage, text: text)
            apply(SyntaxTheme.comment, regex: "/\\*[\\s\\S]*?\\*/", to: storage, text: text)
        }
    }

    // MARK: - Shell

    private func applyShell(to storage: NSTextStorage, text: String) {
        let keywords = [
            "export", "alias", "function", "local", "return", "if", "then", "else",
            "elif", "fi", "for", "while", "do", "done", "case", "esac", "in",
            "source", "eval", "unset", "set", "echo", "cd"
        ]
        let kwPattern = "\\b(?:" + keywords.joined(separator: "|") + ")\\b"
        apply(SyntaxTheme.keyword, regex: kwPattern, to: storage, text: text)

        // Funktionsdefinitionen: name() {
        apply(SyntaxTheme.function, regex: "^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\)",
              to: storage, text: text, group: 1, options: [.anchorsMatchLines])
        // Alias-Name: alias NAME=
        apply(SyntaxTheme.function, regex: "\\balias\\s+([A-Za-z0-9_-]+)=",
              to: storage, text: text, group: 1)

        // Zahlen
        apply(SyntaxTheme.number, regex: "(?<![\\w])-?\\d+(?:\\.\\d+)?", to: storage, text: text)
        // Variablen: $VAR, ${VAR}, $(...)
        apply(SyntaxTheme.variable, regex: "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?",
              to: storage, text: text)
        // Strings
        apply(SyntaxTheme.string, regex: "\"(?:[^\"\\\\]|\\\\.)*\"", to: storage, text: text)
        apply(SyntaxTheme.string, regex: "'[^']*'", to: storage, text: text)
        // Kommentare zuletzt
        apply(SyntaxTheme.comment, regex: "(^|\\s)#[^\\n]*", to: storage, text: text)
    }

    // MARK: - YAML

    private func applyYAML(to storage: NSTextStorage, text: String) {
        // Schlüssel am Zeilenanfang (ggf. eingerückt, ggf. nach Listen-"- "): key:
        // Der Lookahead verlangt Whitespace/Zeilenende nach dem ":" – so werden
        // URLs wie "http://…" nicht fälschlich als Schlüssel erkannt.
        apply(SyntaxTheme.key,
              regex: "^[ \\t]*(?:-[ \\t]+)?([\\w.\\-]+)[ \\t]*:(?=[ \\t]|$)",
              to: storage, text: text, group: 1, options: [.anchorsMatchLines])
        // Listen-Bindestriche am Zeilenanfang
        apply(SyntaxTheme.punctuation,
              regex: "^[ \\t]*(-)(?=[ \\t])",
              to: storage, text: text, group: 1, options: [.anchorsMatchLines])
        // Zahlen (nicht innerhalb von Bezeichnern/Versionsnummern wie v4-flash)
        apply(SyntaxTheme.number,
              regex: "(?<![\\w.\\-])-?\\d+(?:\\.\\d+)?\\b", to: storage, text: text)
        // true / false / null
        apply(SyntaxTheme.constant,
              regex: "\\b(?:true|false|null)\\b",
              to: storage, text: text, options: [.caseInsensitive])
        // Anker/Env-Referenzen: ${VAR}, $VAR
        apply(SyntaxTheme.variable, regex: "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?",
              to: storage, text: text)
        // Strings
        apply(SyntaxTheme.string, regex: "\"(?:[^\"\\\\]|\\\\.)*\"", to: storage, text: text)
        apply(SyntaxTheme.string, regex: "'[^']*'", to: storage, text: text)
        // Kommentare zuletzt
        apply(SyntaxTheme.comment, regex: "(^|\\s)#[^\\n]*", to: storage, text: text)
    }
}
