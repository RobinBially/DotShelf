import SwiftUI
import AppKit

/// Der Editor-Platz eines Skript-Laufs: Terminal, Titel und eigene Toolbar.
struct TerminalDetailView: View {
    @EnvironmentObject var store: Store
    @ObservedObject var session: TerminalSession

    var body: some View {
        TerminalPane(session: session)
            .navigationTitle(session.title)
            .navigationSubtitle(session.prettyWorkingDirectory)
            .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { session.rerun() } label: {
                Label(L10n.text("Rerun"), systemImage: "arrow.clockwise")
            }
            .disabled(session.isRunning)
            .help(L10n.text("Run the command again"))

            Button { session.stop() } label: {
                Label(L10n.text("Stop"), systemImage: "stop.fill")
            }
            .disabled(!session.isRunning)
            .help(L10n.text("Stop the running script (⌘.)"))

            Button { session.clearOutput() } label: {
                Label(L10n.text("Clear"), systemImage: "eraser")
            }
            .help(L10n.text("Clear the output"))

            // Auch von hier aus lässt sich ein weiteres Terminal öffnen.
            Button { store.openTerminal(in: session.workingDirectory) } label: {
                Label(L10n.text("Open Terminal"), systemImage: "terminal.fill")
            }
            .help(L10n.text("Open Terminal"))

            Button { store.closeSession(session) } label: {
                Label(L10n.text("Close"), systemImage: "xmark")
            }
            .help(L10n.text("Close the terminal"))
        }
    }

}

/// Terminal zu einem Skript-Lauf: Ausgabe, Eingabe und Cursor.
struct TerminalView: NSViewRepresentable {

    @ObservedObject var session: TerminalSession
    var fontSize: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = TerminalTheme.background

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)

        let textView = TerminalTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                        textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = TerminalTheme.background
        textView.insertionPointColor = .clear
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = false
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView, session: session)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.session = session
        context.coordinator.fontSize = fontSize
        context.coordinator.isInteractive = session.isRunning
        context.coordinator.textView?.isInteractive = session.isRunning
        context.coordinator.syncSize()
        context.coordinator.render()
        context.coordinator.requestFocusIfNeeded()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator {
        weak var textView: TerminalTextView?
        weak var scrollView: NSScrollView?
        var session: TerminalSession?
        var fontSize: Double = 13
        var isInteractive = false

        private var renderedVersion = -1
        private var renderedFontSize: Double = -1
        private var renderedCursor = false
        private var focusedSessionID: UUID?
        private var columns = 0
        private var rows = 0
        private var observers: [NSObjectProtocol] = []

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }

        func attach(scrollView: NSScrollView, textView: TerminalTextView, session: TerminalSession) {
            self.scrollView = scrollView
            self.textView = textView
            self.session = session
            textView.onInput = { [weak session] data in session?.send(data) }
            textView.onInterrupt = { [weak session] in session?.stop() }
            textView.onFocusChange = { [weak self] _ in self?.render(force: true) }

            scrollView.contentView.postsFrameChangedNotifications = true
            let observer = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.syncSize()
                        self?.render()
                    }
                }
            observers.append(observer)

            requestFocusIfNeeded()
        }

        /// Tastatur ohne Klick ins Terminal: Sonst tippt man ins Leere, weil
        /// der Fokus noch im Dialog oder in der Seitenleiste steht. Klappt der
        /// erste Versuch nicht (Dialog schließt gerade erst), wird kurz
        /// nachgefasst.
        func requestFocusIfNeeded(attempt: Int = 0) {
            guard let session, let textView, session.isRunning else { return }
            guard focusedSessionID != session.id else { return }
            if let window = textView.window, window.isKeyWindow, window.attachedSheet == nil {
                focusedSessionID = session.id
                window.makeFirstResponder(textView)
                render(force: true)
                return
            }
            guard attempt < 6 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                MainActor.assumeIsolated { self?.requestFocusIfNeeded(attempt: attempt + 1) }
            }
        }

        /// Meldet dem Terminal die aktuelle Zeichen- und Zeilenzahl des Bereichs.
        func syncSize() {
            guard let scrollView, let session else { return }
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
            let bounds = scrollView.contentView.bounds
            guard advance > 0, bounds.width > 80, bounds.height > 40 else { return }
            let newColumns = max(40, min(500, Int((bounds.width - 28) / advance)))
            let lineHeight = max(1, NSLayoutManager().defaultLineHeight(for: font))
            let newRows = max(5, min(200, Int(bounds.height / lineHeight)))
            guard newColumns != columns || newRows != rows else { return }
            columns = newColumns
            rows = newRows
            session.resize(columns: newColumns, rows: newRows)
        }

        func render(force: Bool = false) {
            guard let textView, let session else { return }
            let showCursor = isInteractive && session.isRunning
                && textView.window?.firstResponder === textView
            guard force
                    || renderedVersion != session.outputVersion
                    || renderedFontSize != fontSize
                    || renderedCursor != showCursor else { return }
            renderedVersion = session.outputVersion
            renderedFontSize = fontSize
            renderedCursor = showCursor

            let atBottom = isAtBottom()
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(
                session.buffer.attributedString(showCursor: showCursor, fontSize: fontSize))
            let length = (textView.string as NSString).length
            if selection.location <= length {
                textView.setSelectedRange(NSRange(location: selection.location,
                                                  length: min(selection.length, length - selection.location)))
            }
            if atBottom { textView.scrollToEndOfDocument(nil) }
        }

        private func isAtBottom() -> Bool {
            guard let scrollView else { return true }
            let visible = scrollView.documentVisibleRect
            let height = scrollView.documentView?.frame.height ?? 0
            return visible.maxY >= height - 24
        }
    }
}

/// NSTextView als Terminalfläche: Tastatur geht an den Prozess, Auswahl und
/// Kopieren bleiben normal nutzbar.
final class TerminalTextView: NSTextView {

    var onInput: ((Data) -> Void)?
    var onInterrupt: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var isInteractive = false

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        guard isInteractive, !event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }
        guard let characters = event.characters,
              let scalar = characters.unicodeScalars.first else {
            super.keyDown(with: event)
            return
        }
        if let sequence = Self.escapeSequence(for: scalar) {
            onInput?(Data(sequence.utf8))
            return
        }
        switch scalar {
        case "\u{3}":             // Ctrl-C
            onInterrupt?()
        case "\u{4}":             // Ctrl-D
            onInput?(Data([0x04]))
        case "\r", "\n":
            onInput?(Data([0x0D]))
        case "\u{7F}":
            onInput?(Data([0x7F]))
        case "\t":
            onInput?(Data([0x09]))
        default:
            if scalar.value < 0x20 {
                onInput?(Data([UInt8(scalar.value)]))
            } else if scalar.value >= 0xF000 {
                return   // unbekannte Funktionstaste
            } else {
                onInput?(Data(characters.utf8))
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isInteractive, event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if isInteractive, let text = NSPasteboard.general.string(forType: .string) {
            onInput?(Data(text.utf8))
        } else {
            super.paste(sender)
        }
    }

    /// Sondertasten als die Sequenzen, die ein Terminal sendet.
    private static func escapeSequence(for scalar: Unicode.Scalar) -> String? {
        switch Int(scalar.value) {
        case 0xF700: return "\u{1B}[A"      // Pfeil hoch
        case 0xF701: return "\u{1B}[B"      // Pfeil runter
        case 0xF703: return "\u{1B}[C"      // Pfeil rechts
        case 0xF702: return "\u{1B}[D"      // Pfeil links
        case 0xF729: return "\u{1B}[H"      // Pos 1
        case 0xF72B: return "\u{1B}[F"      // Ende
        case 0xF728: return "\u{1B}[3~"     // Entf
        case 0xF72C: return "\u{1B}[5~"     // Bild hoch
        case 0xF72D: return "\u{1B}[6~"     // Bild runter
        default: return nil
        }
    }
}

/// Der Terminal-Bereich im Editor: Ausgabe plus Statuszeile.
struct TerminalPane: View {
    @EnvironmentObject var store: Store
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack(spacing: 0) {
            TerminalView(session: session, fontSize: store.fontSize)
                .id(session.id)
            Divider()
            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            statusLabel
            Text(session.command.isEmpty ? L10n.text("Shell") : session.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(session.command)
            Spacer()
            Text(session.prettyWorkingDirectory)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            if session.isRunning {
                // Laufende Zeit mitzählen, statt sie erst am Ende zu zeigen.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(session.durationText)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            } else {
                Text(session.durationText)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            ZoomControl()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch session.status {
        case .running:
            HStack(spacing: 6) {
                // Das Rädchen läuft nur, wenn wirklich etwas arbeitet. Eine
                // Shell an der Eingabeaufforderung ist bereit, nicht beschäftigt.
                if session.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.secondary)
                }
                Text(session.statusText)
                    .foregroundStyle(.secondary)
            }
        case .exited(let code, let stopped):
            Label(session.statusText,
                  systemImage: (stopped || code == 0) ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(stopped ? Color.secondary : (code == 0 ? Color.green : Color.red))
        case .signaled:
            Label(session.statusText,
                  systemImage: session.hasFailed ? "xmark.circle.fill" : "stop.circle.fill")
                .foregroundStyle(session.hasFailed ? Color.red : Color.secondary)
        case .failed:
            Label(session.statusText, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}
