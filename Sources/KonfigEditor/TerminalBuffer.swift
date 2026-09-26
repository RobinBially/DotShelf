import AppKit

/// Farbe einer Terminal-Zelle: die Standard-16, die xterm-256-Palette oder
/// ein True-Color-Wert aus SGR-Sequenzen.
enum TerminalColor: Hashable {
    case indexed(Int)
    case rgb(UInt8, UInt8, UInt8)
}

/// Zeichenstil einer Zelle (die für Skript-Ausgaben relevanten SGR-Attribute).
struct TerminalStyle: Equatable {
    var foreground: TerminalColor?
    var background: TerminalColor?
    var bold = false
    var underline = false
    var inverse = false
}

struct TerminalCell: Equatable {
    var character: Character = " "
    var style = TerminalStyle()
}

/// Farbpalette des Terminals. Die Farben sind dynamisch (hell/dunkel), damit
/// ein gerenderter Text beim Aussehenwechsel nicht neu gebaut werden muss.
enum TerminalTheme {

    static let foreground = SyntaxTheme.foreground
    static let background = SyntaxTheme.editorBackground

    private static let standard: [NSColor] = [
        pick((59, 63, 69), (92, 99, 112)),      // 0 schwarz
        pick((193, 65, 60), (224, 108, 117)),   // 1 rot
        pick((62, 123, 51), (152, 195, 121)),   // 2 grün
        pick((160, 122, 0), (229, 192, 123)),   // 3 gelb
        pick((47, 98, 196), (97, 175, 239)),    // 4 blau
        pick((139, 63, 168), (198, 120, 221)),  // 5 magenta
        pick((28, 124, 140), (86, 182, 194)),   // 6 cyan
        pick((120, 126, 136), (171, 178, 191)), // 7 weiß (hell: lesbar als Grau)
        pick((122, 127, 138), (110, 118, 129)), // 8 helles Schwarz
        pick((224, 85, 85), (255, 130, 130)),   // 9 helles Rot
        pick((78, 158, 63), (180, 220, 150)),   // 10 helles Grün
        pick((192, 154, 0), (245, 215, 150)),   // 11 helles Gelb
        pick((63, 125, 224), (130, 190, 255)),  // 12 helles Blau
        pick((168, 85, 200), (220, 160, 235)),  // 13 helles Magenta
        pick((42, 163, 181), (120, 215, 225)),  // 14 helles Cyan
        pick((60, 64, 72), (235, 238, 242))     // 15 helles Weiß
    ]

    private static var cache: [TerminalColor: NSColor] = [:]

    /// Übersetzt eine Terminal-Farbe in eine NSColor (nil = Standardfarbe).
    static func nsColor(for color: TerminalColor?) -> NSColor? {
        guard let color else { return nil }
        if let cached = cache[color] { return cached }
        let resolved: NSColor
        switch color {
        case .indexed(let index):
            resolved = indexedColor(index)
        case .rgb(let red, let green, let blue):
            resolved = NSColor(srgbRed: CGFloat(red) / 255,
                               green: CGFloat(green) / 255,
                               blue: CGFloat(blue) / 255,
                               alpha: 1)
        }
        cache[color] = resolved
        return resolved
    }

    private static func indexedColor(_ index: Int) -> NSColor {
        if index < 16 { return standard[max(0, index)] }
        if index < 232 {
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255]
            let value = index - 16
            return NSColor(srgbRed: steps[value / 36] / 255,
                           green: steps[(value / 6) % 6] / 255,
                           blue: steps[value % 6] / 255,
                           alpha: 1)
        }
        let level = CGFloat(8 + (min(index, 255) - 232) * 10) / 255
        return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
    }

    private static func pick(_ light: (Int, Int, Int), _ dark: (Int, Int, Int)) -> NSColor {
        SyntaxTheme.color(light, dark)
    }
}

/// Ein Zeilenraster mit Cursor und so viel ANSI-Semantik, wie Skript-Ausgaben
/// brauchen: Farben, Fortschrittszeilen mit Wagenrücklauf, Löschen und
/// Cursor-Steuerung. Kein vollständiger Emulator (keine Scroll-Regionen,
/// keine Zeichensätze).
final class TerminalBuffer {

    /// Obergrenze des Scrollbacks; ältere Zeilen fallen oben heraus.
    static let maxRows = 3000
    static let defaultColumns = 100

    private(set) var columns: Int
    private(set) var version = 0
    private(set) var cursorVisible = true

    private var rows: [[TerminalCell]] = [[]]
    private var row = 0
    private var column = 0
    private var pendingWrap = false
    private var pen = TerminalStyle()
    private var savedCursor: (row: Int, column: Int)?
    private var parser = Parser.ground
    private var carry: [UInt8] = []
    private var cache: Cache?

    private struct Cache {
        let version: Int
        let showCursor: Bool
        let fontSize: Double
        let value: NSAttributedString
    }

    private enum Parser {
        case ground
        case escape
        case csi(String)
        case osc
        case oscEscape
        case skipOne
    }

    init(columns: Int = TerminalBuffer.defaultColumns) {
        self.columns = max(20, columns)
    }

    // MARK: - Ausgabe einspeisen

    func feed(_ data: Data) {
        carry.append(contentsOf: data)
        let split = Self.utf8PrefixLength(carry)
        guard split > 0 else { return }
        let text = String(decoding: carry[0..<split], as: UTF8.self)
        carry.removeFirst(split)
        // Bewusst über Skalare statt über Characters: ein Wagenrücklauf plus
        // Zeilenumbruch bildet in Swift ein Graphem-Cluster, das sonst
        // unerkannt verschwindet.
        for scalar in text.unicodeScalars {
            step(scalar)
        }
        version += 1
    }

    /// Länge des längsten gültigen UTF-8-Präfix; unvollständige Sequenzen am
    /// Ende bleiben im Puffer, bis der Rest eintrifft.
    private static func utf8PrefixLength(_ bytes: [UInt8]) -> Int {
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let expected: Int
            switch byte {
            case 0x00...0x7F: expected = 1
            case 0xC2...0xDF: expected = 2
            case 0xE0...0xEF: expected = 3
            case 0xF0...0xF4: expected = 4
            default: expected = 1   // ungültiges Byte: als Ersatzzeichen dekodieren
            }
            if index + expected > bytes.count { return index }
            index += expected
        }
        return bytes.count
    }

    // MARK: - Raster

    func resize(columns: Int) {
        let clamped = max(20, columns)
        guard clamped != self.columns else { return }
        self.columns = clamped
        column = min(column, clamped - 1)
        pendingWrap = false
        version += 1
    }

    func clear() {
        rows = [[]]
        row = 0
        column = 0
        pendingWrap = false
        pen = TerminalStyle()
        savedCursor = nil
        version += 1
    }

    /// Reiner Text des Puffers (Diagnose und Tests).
    var plainText: String {
        var lines = rows.map { line in
            var text = String(line.map(\.character))
            while text.hasSuffix(" ") { text.removeLast() }
            return text
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    var rowCount: Int { rows.count }

    // MARK: - Rendering

    func attributedString(showCursor: Bool, fontSize: Double) -> NSAttributedString {
        if let cache, cache.version == version,
           cache.showCursor == showCursor, cache.fontSize == fontSize {
            return cache.value
        }
        let value = render(showCursor: showCursor, fontSize: fontSize)
        cache = Cache(version: version, showCursor: showCursor, fontSize: fontSize, value: value)
        return value
    }

    private struct StyleKey: Equatable {
        let foreground: NSColor
        let background: NSColor?
        let bold: Bool
        let underline: Bool
    }

    private struct RenderedCell {
        var character: Character
        var foreground: NSColor
        var background: NSColor?
        var bold: Bool
        var underline: Bool

        var attributes: [NSAttributedString.Key: Any] {
            var result: [NSAttributedString.Key: Any] = [.foregroundColor: foreground]
            if let background { result[.backgroundColor] = background }
            if underline { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            return result
        }

        var styleKey: StyleKey {
            StyleKey(foreground: foreground, background: background,
                     bold: bold, underline: underline)
        }
    }

    private func render(showCursor: Bool, fontSize: Double) -> NSAttributedString {
        let regular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let cursorHere = showCursor && cursorVisible
        let result = NSMutableAttributedString()

        for (index, stored) in rows.enumerated() {
            let line = stored
            var end = line.count
            while end > 0 {
                let cell = line[end - 1]
                if cell.character == " ", cell.style.background == nil { end -= 1 } else { break }
            }
            if cursorHere, index == row {
                end = max(end, column + 1)
            }

            var runText = ""
            var runCell: RenderedCell?
            var position = 0
            while position < end {
                let cell = position < line.count ? line[position] : TerminalCell()
                let rendered = renderedCell(cell, isCursor: cursorHere && index == row && position == column)
                if let current = runCell, current.styleKey == rendered.styleKey {
                    runText.append(rendered.character)
                } else {
                    append(runText, runCell, font: regular, boldFont: bold, to: result)
                    runText = String(rendered.character)
                    runCell = rendered
                }
                position += 1
            }
            append(runText, runCell, font: regular, boldFont: bold, to: result)
            result.append(NSAttributedString(string: "\n", attributes: [.font: regular]))
        }
        return result
    }

    private func append(_ text: String, _ cell: RenderedCell?, font: NSFont,
                        boldFont: NSFont, to result: NSMutableAttributedString) {
        guard let cell, !text.isEmpty else { return }
        var attributes = cell.attributes
        attributes[.font] = cell.bold ? boldFont : font
        result.append(NSAttributedString(string: text, attributes: attributes))
    }

    private func renderedCell(_ cell: TerminalCell, isCursor: Bool) -> RenderedCell {
        var foreground = TerminalTheme.nsColor(for: cell.style.foreground) ?? TerminalTheme.foreground
        var background = TerminalTheme.nsColor(for: cell.style.background)
        if cell.style.inverse {
            let newForeground = background ?? TerminalTheme.background
            let newBackground = foreground
            foreground = newForeground
            background = newBackground
        }
        if isCursor {
            let newForeground = background ?? TerminalTheme.background
            background = foreground
            foreground = newForeground
        }
        return RenderedCell(character: cell.character, foreground: foreground,
                            background: background, bold: cell.style.bold,
                            underline: cell.style.underline || isCursor)
    }

    // MARK: - Parser

    private func step(_ scalar: Unicode.Scalar) {
        switch parser {
        case .ground: handleGround(scalar)
        case .escape: handleEscape(scalar)
        case .csi(let collected): handleCSI(scalar, collected: collected)
        case .osc: if scalar == "\u{7}" || scalar == "\u{18}" { parser = .ground }
        case .oscEscape: parser = scalar == "\\" ? .ground : .osc
        case .skipOne: parser = .ground
        }
    }

    private func handleGround(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "\u{1B}":
            parser = .escape
        case "\n", "\u{B}", "\u{C}":
            newLine()
            pendingWrap = false
        case "\r":
            column = 0
            pendingWrap = false
        case "\u{8}":
            if column > 0 { column -= 1 }
            pendingWrap = false
        case "\t":
            advanceTab()
        case "\u{7}":
            break
        default:
            guard scalar.value >= 0x20, scalar.value != 0x7F else { return }
            put(scalar)
        }
    }

    private func handleEscape(_ scalar: Unicode.Scalar) {
        parser = .ground
        switch scalar {
        case "[": parser = .csi("")
        case "]", "P", "^", "_": parser = .osc
        case "c": clear()
        case "7": savedCursor = (row, column)
        case "8":
            if let saved = savedCursor {
                row = min(saved.row, rows.count)
                column = min(saved.column, columns - 1)
                pendingWrap = false
            }
        case "M": reverseIndex()
        case "D": newLine()
        case "E":
            column = 0
            newLine()
        case "(", ")", "*", "+", "#", " ", "%": parser = .skipOne
        default: break
        }
    }

    private func handleCSI(_ scalar: Unicode.Scalar, collected: String) {
        let value = scalar.value
        if value == 0x18 || value == 0x1A {
            parser = .ground
            return
        }
        if value >= 0x40, value <= 0x7E {
            parser = .ground
            execute(final: scalar, params: collected)
            return
        }
        guard value >= 0x20, value <= 0x3F else {
            parser = .ground
            return
        }
        parser = .csi(collected + String(Character(scalar)))
    }

    private func execute(final: Unicode.Scalar, params: String) {
        let isPrivate = params.hasPrefix("?") || params.hasPrefix(">") || params.hasPrefix("<")
        let sanitized = String(params.filter { $0.isNumber || $0 == ";" })
        let numbers = sanitized.split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        func value(_ index: Int, default fallback: Int = 1) -> Int {
            guard index < numbers.count, numbers[index] > 0 else { return fallback }
            return numbers[index]
        }

        switch final {
        case "m":
            applySGR(numbers)
        case "K":
            eraseInLine(mode: numbers.first ?? 0)
        case "J":
            eraseInDisplay(mode: numbers.first ?? 0)
        case "A":
            moveRow(by: -value(0))
            pendingWrap = false
        case "B", "e":
            moveRow(by: value(0))
            pendingWrap = false
        case "C", "a":
            column = min(columns - 1, column + value(0))
            pendingWrap = false
        case "D":
            column = max(0, column - value(0))
            pendingWrap = false
        case "E":
            column = 0
            moveRow(by: value(0))
            pendingWrap = false
        case "F":
            column = 0
            moveRow(by: -value(0))
            pendingWrap = false
        case "G", "\u{60}":
            column = min(columns - 1, max(0, value(0) - 1))
            pendingWrap = false
        case "d":
            moveRow(to: value(0) - 1)
        case "H", "f":
            moveRow(to: value(0) - 1)
            column = min(columns - 1, max(0, value(1) - 1))
            pendingWrap = false
        case "s":
            savedCursor = (row, column)
        case "u":
            if let saved = savedCursor {
                row = min(saved.row, rows.count)
                column = min(saved.column, columns - 1)
            }
        case "X":
            eraseCharacters(value(0))
        case "h", "l":
            if isPrivate, params.hasPrefix("?"), numbers.contains(25) { cursorVisible = final == "h" }
        default:
            break
        }
    }

    private func applySGR(_ numbers: [Int]) {
        let codes = numbers.isEmpty ? [0] : numbers
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: pen = TerminalStyle()
            case 1: pen.bold = true
            case 4: pen.underline = true
            case 7: pen.inverse = true
            case 22: pen.bold = false
            case 24: pen.underline = false
            case 27: pen.inverse = false
            case 30...37: pen.foreground = .indexed(code - 30)
            case 39: pen.foreground = nil
            case 40...47: pen.background = .indexed(code - 40)
            case 49: pen.background = nil
            case 90...97: pen.foreground = .indexed(code - 82)
            case 100...107: pen.background = .indexed(code - 92)
            case 38, 48:
                let isForeground = code == 38
                if index + 2 < codes.count, codes[index + 1] == 5 {
                    let color = TerminalColor.indexed(codes[index + 2])
                    if isForeground { pen.foreground = color } else { pen.background = color }
                    index += 2
                } else if index + 4 < codes.count, codes[index + 1] == 2 {
                    let color = TerminalColor.rgb(UInt8(clamping: codes[index + 2]),
                                                  UInt8(clamping: codes[index + 3]),
                                                  UInt8(clamping: codes[index + 4]))
                    if isForeground { pen.foreground = color } else { pen.background = color }
                    index += 4
                }
            default: break
            }
            index += 1
        }
    }

    // MARK: - Schreiboperationen

    private func put(_ scalar: Unicode.Scalar) {
        if pendingWrap {
            column = 0
            newLine()
            pendingWrap = false
        }
        ensureRow(row)
        var line = rows[row]
        while line.count <= column { line.append(TerminalCell()) }
        line[column] = TerminalCell(character: Character(scalar), style: pen)
        rows[row] = line
        if column >= columns - 1 {
            column = columns - 1
            pendingWrap = true
        } else {
            column += 1
        }
    }

    private func advanceTab() {
        let target = ((column / 8) + 1) * 8
        while column < target, !pendingWrap { put(" ") }
    }

    private func newLine() {
        ensureRow(row + 1)
        row += 1
        trimScrollback()
    }

    private func reverseIndex() {
        if row > 0 { row -= 1 }
    }

    private func moveRow(by delta: Int) {
        row = min(max(0, row + delta), rows.count)
    }

    private func moveRow(to target: Int) {
        row = min(max(0, target), rows.count)
    }

    private func ensureRow(_ index: Int) {
        while rows.count <= index { rows.append([]) }
        while rows.count > Self.maxRows {
            rows.removeFirst()
            if row > 0 { row -= 1 }
        }
    }

    private func trimScrollback() {
        while rows.count > Self.maxRows {
            rows.removeFirst()
            if row > 0 { row -= 1 }
        }
    }

    private func eraseInLine(mode: Int) {
        ensureRow(row)
        var line = rows[row]
        switch mode {
        case 1:
            let end = min(column, line.count - 1)
            guard end >= 0 else { return }
            for position in 0...end {
                line[position] = TerminalCell(style: TerminalStyle(background: pen.background))
            }
        case 2:
            line = []
        default:
            guard column < line.count else { return }
            line.removeSubrange(column..<line.count)
        }
        rows[row] = line
    }

    private func eraseInDisplay(mode: Int) {
        switch mode {
        case 1:
            for position in 0...row {
                if position == row {
                    eraseInLine(mode: 1)
                } else {
                    rows[position] = []
                }
            }
        case 2, 3:
            rows = Array(repeating: [], count: row + 1)
        default:
            eraseInLine(mode: 0)
            guard row + 1 < rows.count else { return }
            for position in (row + 1)..<rows.count { rows[position] = [] }
        }
    }

    private func eraseCharacters(_ count: Int) {
        ensureRow(row)
        var line = rows[row]
        guard column < line.count else { return }
        let end = min(line.count - 1, column + count - 1)
        for position in column...end {
            line[position] = TerminalCell(style: TerminalStyle(background: pen.background))
        }
        rows[row] = line
    }
}
