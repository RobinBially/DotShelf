import AppKit

/// NSTextView mit Editor-Komfort. Tastenkürzel orientieren sich an der
/// IntelliJ-macOS-Keymap:
///   ⌘/        – Zeilen ein-/auskommentieren
///   Tab / ⇧Tab – Auswahl ein-/ausrücken
///   ⌘D        – Zeile/Auswahl duplizieren
///   ⌘⌫        – Zeile(n) löschen
///   ⌥⇧↑ / ⌥⇧↓ – Zeile(n) nach oben/unten verschieben
///   ⌘F, ⌘G / ⌘⇧G – Suchen / nächster bzw. vorheriger Treffer
final class CodeTextView: NSTextView {

    /// Kommentar-Präfix der aktuellen Sprache, z. B. "//" oder "#".
    var commentPrefix: String = "//"

    /// Einrück-Einheit. Leerzeichen statt Tabs, weil YAML keine Tabs erlaubt.
    private let indentUnit = "  "

    // macOS-Tastencodes (keyCode), unabhängig vom erzeugten Zeichen.
    private enum Key: UInt16 {
        case delete = 51       // Backspace
        case upArrow = 126
        case downArrow = 125
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags
        let commandOnly = mods.contains(.command)
            && !mods.contains(.option)
            && !mods.contains(.control)
        let optionShiftOnly = mods.contains(.option) && mods.contains(.shift)
            && !mods.contains(.command) && !mods.contains(.control)

        // ⌘/ – auf der deutschen Tastatur physisch ⌘⇧7, daher Shift zulassen
        // und auf das erzeugte Zeichen "/" prüfen (statt auf einen keyCode).
        if commandOnly, event.charactersIgnoringModifiers == "/" {
            toggleComment()
            return true
        }

        let chars = event.charactersIgnoringModifiers?.lowercased()

        // ⌘F – Suchleiste einblenden.
        if commandOnly, !mods.contains(.shift), chars == "f" {
            performFindAction(.showFindInterface)
            return true
        }

        // ⌘G / ⌘⇧G – nächster bzw. vorheriger Treffer.
        if commandOnly, chars == "g" {
            performFindAction(mods.contains(.shift) ? .previousMatch : .nextMatch)
            return true
        }

        // ⌘D – Zeile/Auswahl duplizieren.
        if commandOnly, !mods.contains(.shift), chars == "d" {
            duplicateSelectionOrLine()
            return true
        }

        // ⌘⌫ – aktuelle Zeile(n) löschen.
        if mods.contains(.command), !mods.contains(.control),
           event.keyCode == Key.delete.rawValue {
            deleteCurrentLines()
            return true
        }

        // ⌥⇧↑ / ⌥⇧↓ – Zeile(n) verschieben.
        if optionShiftOnly, event.keyCode == Key.upArrow.rawValue {
            moveLines(up: true)
            return true
        }
        if optionShiftOnly, event.keyCode == Key.downArrow.rawValue {
            moveLines(up: false)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Einrücken

    /// Tab: bei Auswahl den Block einrücken, sonst eine Einrück-Einheit einfügen.
    override func insertTab(_ sender: Any?) {
        if selectedRange().length == 0 {
            insertText(indentUnit, replacementRange: selectedRange())
        } else {
            shiftLines(indent: true)
        }
    }

    /// ⇧Tab: berührte Zeilen ausrücken.
    override func insertBacktab(_ sender: Any?) {
        shiftLines(indent: false)
    }

    /// Rückt alle von der Auswahl berührten Zeilen ein bzw. aus.
    private func shiftLines(indent: Bool) {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        guard lineRange.length > 0 else { return }

        var edits: [LineEdit] = []
        ns.enumerateSubstrings(in: lineRange, options: [.byLines]) { sub, subRange, _, _ in
            guard let sub else { return }
            if indent {
                // Leerzeilen nicht einrücken (kein nachgelagerter Whitespace).
                guard !sub.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                edits.append(LineEdit(offset: subRange.location, removeLen: 0, insert: self.indentUnit))
            } else if sub.first == "\t" {
                edits.append(LineEdit(offset: subRange.location, removeLen: 1, insert: ""))
            } else {
                let leadingSpaces = sub.prefix { $0 == " " }.count
                guard leadingSpaces > 0 else { return }
                let remove = min(leadingSpaces, self.indentUnit.count)
                edits.append(LineEdit(offset: subRange.location, removeLen: remove, insert: ""))
            }
        }
        applyLineEdits(edits, floor: lineRange.location)
    }

    // MARK: - Duplizieren / Löschen / Verschieben

    /// ⌘D: Auswahl direkt dahinter einfügen, sonst die aktuelle Zeile darunter.
    private func duplicateSelectionOrLine() {
        guard let textStorage else { return }
        let ns = string as NSString
        let sel = selectedRange()

        if sel.length > 0 {
            let copy = ns.substring(with: sel)
            let at = sel.location + sel.length
            let range = NSRange(location: at, length: 0)
            guard shouldChangeText(in: range, replacementString: copy) else { return }
            textStorage.replaceCharacters(in: range, with: copy)
            didChangeText()
            setSelectedRange(NSRange(location: at, length: (copy as NSString).length))
            return
        }

        let lineRange = ns.lineRange(for: sel)
        var lineText = ns.substring(with: lineRange)
        // Letzte Zeile ohne abschließendes \n: Zeilenumbruch voranstellen.
        let prependedNewline = !lineText.hasSuffix("\n")
        if prependedNewline { lineText = "\n" + lineText }

        let at = lineRange.location + lineRange.length
        let range = NSRange(location: at, length: 0)
        guard shouldChangeText(in: range, replacementString: lineText) else { return }
        textStorage.replaceCharacters(in: range, with: lineText)
        didChangeText()

        // Cursor in die Kopie, gleiche Spalte.
        let caretColumn = sel.location - lineRange.location
        let copyStart = at + (prependedNewline ? 1 : 0)
        setSelectedRange(NSRange(location: copyStart + caretColumn, length: 0))
    }

    /// ⌘⌫: alle von der Auswahl berührten Zeilen entfernen.
    private func deleteCurrentLines() {
        guard let textStorage else { return }
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        guard lineRange.length > 0, shouldChangeText(in: lineRange, replacementString: "") else { return }
        textStorage.replaceCharacters(in: lineRange, with: "")
        didChangeText()
        let loc = min(lineRange.location, (string as NSString).length)
        setSelectedRange(NSRange(location: loc, length: 0))
    }

    /// ⌥⇧↑ / ⌥⇧↓: berührten Zeilenblock mit der Nachbarzeile tauschen.
    private func moveLines(up: Bool) {
        guard let textStorage else { return }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)

        let combined: NSRange
        let replacement: String
        let shift: Int

        if up {
            guard lineRange.location > 0 else { return }
            let prev = ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
            combined = NSRange(location: prev.location,
                               length: lineRange.location + lineRange.length - prev.location)
            var p = ns.substring(with: prev)
            var b = ns.substring(with: lineRange)
            // Block ist letzte Zeile (ohne \n): Zeilenenden umhängen.
            if !b.hasSuffix("\n") {
                p = String(p.dropLast())
                b += "\n"
            }
            replacement = b + p
            shift = prev.location - lineRange.location
        } else {
            let end = lineRange.location + lineRange.length
            guard end < ns.length else { return }
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            combined = NSRange(location: lineRange.location,
                               length: next.location + next.length - lineRange.location)
            var b = ns.substring(with: lineRange)
            var n = ns.substring(with: next)
            // Nachbarzeile ist letzte Zeile (ohne \n): Zeilenenden umhängen.
            if !n.hasSuffix("\n") {
                b = String(b.dropLast())
                n += "\n"
            }
            replacement = n + b
            shift = (n as NSString).length
        }

        guard shouldChangeText(in: combined, replacementString: replacement) else { return }
        undoManager?.beginUndoGrouping()
        textStorage.replaceCharacters(in: combined, with: replacement)
        didChangeText()
        undoManager?.endUndoGrouping()

        let newLoc = max(0, sel.location + shift)
        setSelectedRange(NSRange(location: newLoc, length: sel.length))
    }

    // MARK: - Suche

    /// Aktionen der eingebauten Such-/Treffer-Leiste. Die Rohwerte entsprechen
    /// den Tags, die `performFindPanelAction(_:)` vom Sender erwartet.
    private enum FindAction: Int {
        case showFindInterface = 1
        case nextMatch = 2
        case previousMatch = 3
    }

    /// Löst eine Aktion der eingebauten Suchleiste über deren Tag-Konvention aus.
    private func performFindAction(_ action: FindAction) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performFindPanelAction(item)
    }

    // MARK: - Kommentieren

    /// Kommentiert die von der Auswahl berührten Zeilen ein oder aus.
    /// Die ursprüngliche Cursor-/Auswahlposition bleibt erhalten – es wird
    /// NICHT die ganze Zeile markiert.
    func toggleComment() {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        guard lineRange.length > 0 else { return }

        let prefix = commentPrefix
        let withSpace = prefix + " "

        // Inhaltszeilen (ohne Leerzeilen) mit absoluten Bereichen sammeln.
        var contentLines: [NSRange] = []
        ns.enumerateSubstrings(in: lineRange, options: [.byLines]) { sub, subRange, _, _ in
            if let sub, !sub.trimmingCharacters(in: .whitespaces).isEmpty {
                contentLines.append(subRange)
            }
        }
        guard !contentLines.isEmpty else { return }

        // Auskommentieren nur, wenn ALLE Inhaltszeilen bereits kommentiert sind.
        let allCommented = contentLines.allSatisfy {
            ns.substring(with: $0).trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }

        // Edits pro Zeile berechnen.
        var edits: [LineEdit] = []
        for range in contentLines {
            let line = ns.substring(with: range)
            let leading = line.prefix { $0 == " " || $0 == "\t" }.count
            let insOffset = range.location + leading
            if allCommented {
                let afterWS = String(line.dropFirst(leading))
                guard afterWS.hasPrefix(prefix) else { continue }
                var removeLen = prefix.count
                if afterWS.dropFirst(prefix.count).first == " " { removeLen += 1 }
                edits.append(LineEdit(offset: insOffset, removeLen: removeLen, insert: ""))
            } else {
                edits.append(LineEdit(offset: insOffset, removeLen: 0, insert: withSpace))
            }
        }
        applyLineEdits(edits, floor: lineRange.location)
    }

    // MARK: - Gemeinsame Edit-Anwendung

    private struct LineEdit {
        let offset: Int      // absolute Position der Änderung
        let removeLen: Int   // zu entfernende Zeichen
        let insert: String   // einzufügender Text
        var delta: Int { (insert as NSString).length - removeLen }
    }

    /// Wendet mehrere Zeilen-Edits in einer Undo-Gruppe an und verschiebt die
    /// bestehende Auswahl entsprechend mit (kein Voll-Zeilen-Select).
    private func applyLineEdits(_ edits: [LineEdit], floor: Int) {
        guard !edits.isEmpty, let textStorage else { return }
        let sel = selectedRange()
        let selStart = sel.location
        let selEnd = sel.location + sel.length

        var startShift = 0
        var lengthShift = 0
        for e in edits {
            if e.offset < selStart {
                startShift += e.delta
            } else if e.offset < selEnd {
                lengthShift += e.delta
            }
        }

        // Edits von hinten nach vorne anwenden, damit Offsets gültig bleiben.
        undoManager?.beginUndoGrouping()
        for e in edits.sorted(by: { $0.offset > $1.offset }) {
            let range = NSRange(location: e.offset, length: e.removeLen)
            if shouldChangeText(in: range, replacementString: e.insert) {
                textStorage.replaceCharacters(in: range, with: e.insert)
                didChangeText()
            }
        }
        undoManager?.endUndoGrouping()

        let newLoc = max(floor, selStart + startShift)
        let newLen = max(0, sel.length + lengthShift)
        setSelectedRange(NSRange(location: newLoc, length: newLen))
    }
}

extension ConfigLanguage {
    /// Kommentar-Präfix für ⌘/.
    var commentPrefix: String {
        switch self {
        case .json, .jsonc: return "//"
        case .shell, .yaml: return "#"
        }
    }
}
