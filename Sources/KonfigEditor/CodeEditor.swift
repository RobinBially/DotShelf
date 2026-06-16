import SwiftUI
import AppKit

/// SwiftUI-Wrapper um ein NSTextView mit Monospace-Font, Zeilennummern,
/// Syntax-Highlighting, ⌘/-Kommentieren, Auto-Kopieren bei Auswahl und Zoom.
struct CodeEditor: NSViewRepresentable {

    @Binding var text: String
    var language: ConfigLanguage
    var fontSize: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SyntaxTheme.editorBackground

        // TextKit-1-Stack manuell aufbauen. Wichtig: textView(frame:textContainer:)
        // erzwingt TextKit 1 – nötig, damit der Zeilennummern-Ruler (layoutManager-API)
        // das Glyph-Rendering nicht auf einen kaputten TextKit-1-Fallback zwingt.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200),
                                    textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.backgroundColor = SyntaxTheme.editorBackground
        textView.insertionPointColor = SyntaxTheme.foreground
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.commentPrefix = language.commentPrefix
        // Eingebaute Suchleiste (⌘F) mit inkrementeller Treffer-Hervorhebung.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.string = text

        scrollView.documentView = textView

        // Zeilennummern
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.applyFont()
        context.coordinator.applyHighlight(language: language)

        // Ruler beim Scrollen / Bearbeiten neu zeichnen
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main) { [weak ruler] _ in ruler?.needsDisplay = true }
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.language = language
        textView.commentPrefix = language.commentPrefix

        if context.coordinator.fontSize != CGFloat(fontSize) {
            context.coordinator.fontSize = CGFloat(fontSize)
            context.coordinator.applyFont()
            context.coordinator.applyHighlight(language: language)
        }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            context.coordinator.applyHighlight(language: language)
            textView.setSelectedRange(
                NSRange(location: min(selected.location, text.utf16.count), length: 0))
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeEditor
        weak var textView: CodeTextView?
        weak var ruler: LineNumberRulerView?
        var language: ConfigLanguage
        var fontSize: CGFloat
        private var highlightWorkItem: DispatchWorkItem?

        var font: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }

        init(_ parent: CodeEditor) {
            self.parent = parent
            self.language = parent.language
            self.fontSize = CGFloat(parent.fontSize)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            scheduleHighlight()
            ruler?.needsDisplay = true
        }

        /// Auto-Kopieren: markierter Text landet sofort in der Zwischenablage.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            let selected = (textView.string as NSString).substring(with: range)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selected, forType: .string)
        }

        func applyHighlight(language: ConfigLanguage) {
            guard let storage = textView?.textStorage else { return }
            SyntaxHighlighter(font: font).highlight(storage, language: language)
        }

        /// Schrift (Zoom) auf TextView, Tabbreite und Ruler anwenden.
        func applyFont() {
            guard let textView = textView else { return }
            textView.font = font

            let para = NSMutableParagraphStyle()
            para.tabStops = []
            para.defaultTabInterval = ("    " as NSString)
                .size(withAttributes: [.font: font]).width
            textView.defaultParagraphStyle = para
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: SyntaxTheme.foreground,
                .paragraphStyle: para
            ]

            ruler?.labelFontSize = max(9, fontSize - 2)
            ruler?.ruleThickness = max(44, fontSize * 3.2)
            ruler?.needsDisplay = true
        }

        private func scheduleHighlight() {
            highlightWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.applyHighlight(language: self.language)
            }
            highlightWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        }
    }
}
