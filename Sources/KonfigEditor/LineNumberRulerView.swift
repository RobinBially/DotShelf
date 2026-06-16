import AppKit

/// Zeigt Zeilennummern links neben dem NSTextView.
final class LineNumberRulerView: NSRulerView {

    private weak var textView: NSTextView?

    /// Schriftgröße der Zeilennummern (skaliert mit dem Editor-Zoom).
    var labelFontSize: CGFloat = 11 {
        didSet { needsDisplay = true }
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        // Hintergrund NUR im schmalen Nummern-Streifen füllen – niemals breiter,
        // sonst würde der Text dahinter übermalt.
        let gutter = NSRect(x: bounds.minX, y: rect.minY,
                            width: ruleThickness, height: rect.height)
        SyntaxTheme.editorBackground.setFill()
        gutter.fill()

        let content = textView.string as NSString
        let visibleRect = textView.visibleRect
        let inset = textView.textContainerInset.height

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Zeilennummer am Anfang des sichtbaren Bereichs bestimmen
        var lineNumber = 1
        content.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                                    options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        let font = NSFont.monospacedSystemFont(ofSize: labelFontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: SyntaxTheme.lineNumber
        ]

        func drawNumber(_ n: Int, atY y: CGFloat) {
            let s = "\(n)" as NSString
            let size = s.size(withAttributes: attrs)
            let x = ruleThickness - size.width - 8
            s.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }

        // Über die sichtbaren Zeilenfragmente iterieren
        content.enumerateSubstrings(in: charRange,
                                    options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let rectForLine = layoutManager.lineFragmentRect(
                forGlyphAt: layoutManager.glyphIndexForCharacter(at: lineRange.location),
                effectiveRange: nil)
            let y = rectForLine.minY + inset - visibleRect.minY
            drawNumber(lineNumber, atY: y + 1)
            lineNumber += 1
        }

        // Letzte (leere) Zeile, falls Datei mit \n endet
        if content.length == 0 || content.hasSuffix("\n") {
            let usedRect = layoutManager.usedRect(for: container)
            let y = usedRect.maxY + inset - visibleRect.minY
            if y >= 0 && y <= bounds.height {
                drawNumber(lineNumber, atY: y + 1)
            }
        }
    }
}
