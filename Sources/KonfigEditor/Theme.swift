import SwiftUI
import AppKit

/// Farbpalette für Editor & Syntax-Highlighting (passt sich an Hell/Dunkel an).
enum SyntaxTheme {

    static func color(_ light: (Int, Int, Int), _ dark: (Int, Int, Int)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: CGFloat(c.0) / 255.0,
                           green: CGFloat(c.1) / 255.0,
                           blue: CGFloat(c.2) / 255.0,
                           alpha: 1)
        }
    }

    static let foreground = color((40, 44, 52),   (220, 223, 228))
    static let editorBackground = color((250, 250, 252), (30, 32, 38))
    static let lineNumber = color((170, 174, 182), (110, 116, 128))
    static let currentLineBg = color((236, 239, 244), (44, 48, 56))

    // Syntaxfarben (One-Dark / Solarized angelehnt)
    static let keyword  = color((166, 38, 164),  (198, 120, 221)) // export, alias, if …
    static let string   = color((80, 161, 79),   (152, 195, 121)) // "..."
    static let number   = color((152, 104, 1),   (209, 154, 102)) // 42, 3.14
    static let comment  = color((160, 161, 167),  (92, 99, 112))  // // # …
    static let key      = color((61, 116, 219),  (97, 175, 239))  // JSON-Schlüssel
    static let constant = color((196, 80, 80),   (224, 108, 117)) // true/false/null
    static let variable = color((196, 122, 30),  (229, 192, 123)) // $VAR
    static let punctuation = color((120, 124, 130), (130, 136, 148))
    static let function = color((61, 116, 219),  (97, 175, 239))  // funktionsnamen()
}

/// Akzentfarbe pro Sprache – für hübsche Icons in der Sidebar.
extension ConfigLanguage {
    var accent: Color {
        switch self {
        case .json:  return .orange
        case .jsonc: return .pink
        case .shell: return .green
        case .yaml:  return .purple
        }
    }
}

extension ConfigFile {
    /// Effektive Symbolfarbe: eigene Farbe (falls gewählt), sonst Sprach-Akzent.
    var symbolColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) { return color }
        return language.accent
    }
}

extension Color {
    /// Erzeugt eine Farbe aus einem 6-stelligen Hex-String (z. B. "FF9F0A").
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
