import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView(columnVisibility: splitVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: store.sidebarCollapsed ? 72 : 240,
                    ideal: store.sidebarCollapsed ? 72 : 270,
                    max: store.sidebarCollapsed ? 72 : 340)
        } detail: {
            DetailView()
        }
        .background(SidebarSplitGuard(
            minWidth: 72,
            targetWidth: store.sidebarCollapsed ? 72 : 270))
        .background(WindowConfigurator())
        .animation(.easeInOut(duration: 0.18), value: store.sidebarCollapsed)
    }

    private var splitVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { store.splitVisibility },
            set: { visibility in
                store.splitVisibility = visibility == .all ? .all : .all
            }
        )
    }
}

// MARK: - Hover-Hilfe (ohne @State, da SwiftUIMacros im Build fehlt)

/// Hält den Hover-Zustand in einem winzigen ObservableObject.
final class HoverModel: ObservableObject {
    @Published var hovering = false
}

/// Reicht den aktuellen Hover-Zustand an einen ViewBuilder weiter.
struct Hoverable<Content: View>: View {
    @StateObject private var model = HoverModel()
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(model.hovering)
            .onHover { model.hovering = $0 }
    }
}

extension View {
    /// Zeigt über diesem Element den Hand-Cursor, daneben wieder den Pfeil.
    /// Stabil, weil im Popover-Fenster keine Editor-Cursor-Rects konkurrieren.
    func handCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

/// Verhindert, dass die SwiftUI-NavigationSplitView die Sidebar per Divider-Drag
/// unter die Icon-Rail-Breite zieht.
struct SidebarSplitGuard: NSViewRepresentable {
    let minWidth: CGFloat
    let targetWidth: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.scheduleConfiguration(from: view, targetWidth: targetWidth)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.scheduleConfiguration(from: nsView, targetWidth: targetWidth)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(minWidth: minWidth, targetWidth: targetWidth)
    }

    fileprivate func configureSplitView(from view: NSView, coordinator: Coordinator) {
        guard let root = view.window?.contentView ?? view.superview else { return }
        coordinator.attach(to: splitViews(in: root))
        coordinator.enforceMinimumSidebarWidth()
    }

    fileprivate func splitViews(in view: NSView) -> [NSSplitView] {
        var result: [NSSplitView] = []
        if let splitView = view as? NSSplitView {
            result.append(splitView)
        }
        for subview in view.subviews {
            result.append(contentsOf: splitViews(in: subview))
        }
        return result
    }

    final class Coordinator: NSObject {
        private var splitViews: [NSSplitView] = []
        private let minWidth: CGFloat
        private var targetWidth: CGFloat
        private var observers: [NSObjectProtocol] = []
        private var scheduled = false
        private var didInstall = false

        init(minWidth: CGFloat, targetWidth: CGFloat) {
            self.minWidth = minWidth
            self.targetWidth = targetWidth
            super.init()
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func scheduleConfiguration(from view: NSView, targetWidth: CGFloat) {
            let targetChanged = self.targetWidth != targetWidth
            self.targetWidth = targetWidth
            if targetChanged {
                animateSidebarWidth()
            }

            guard !scheduled else { return }
            scheduled = true

            for attempt in 0..<12 {
                let delay = DispatchTime.now() + .milliseconds(attempt * 100)
                DispatchQueue.main.asyncAfter(deadline: delay) { [weak self, weak view] in
                    guard let self, let view else { return }
                    let helper = SidebarSplitGuard(
                        minWidth: self.minWidth,
                        targetWidth: self.targetWidth)
                    helper.configureSplitView(from: view, coordinator: self)
                    if attempt == 11 {
                        self.scheduled = false
                    }
                }
            }
        }

        func attach(to splitViews: [NSSplitView]) {
            let usable = splitViews.filter { $0.arrangedSubviews.count >= 2 }
            guard !usable.isEmpty else { return }
            if self.splitViews.map(ObjectIdentifier.init) == usable.map(ObjectIdentifier.init) {
                return
            }
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            self.splitViews = usable
            didInstall = true
            for splitView in usable {
                let observer = NotificationCenter.default.addObserver(
                    forName: NSSplitView.didResizeSubviewsNotification,
                    object: splitView,
                    queue: .main
                ) { [weak self] _ in
                    self?.enforceMinimumSidebarWidth()
                }
                observers.append(observer)
            }
        }

        func enforceMinimumSidebarWidth() {
            for splitView in splitViews where splitView.arrangedSubviews.count >= 2 {
                let sidebar = splitView.arrangedSubviews[0]
                sidebar.isHidden = false
                if sidebar.frame.width < minWidth {
                    splitView.setPosition(minWidth, ofDividerAt: 0)
                }
            }
        }

        private func animateSidebarWidth() {
            guard didInstall else { return }

            for splitView in splitViews where splitView.arrangedSubviews.count >= 2 {
                let width = splitView.arrangedSubviews[0].frame.width
                guard abs(width - targetWidth) > 1 else { continue }

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    splitView.animator().setPosition(max(minWidth, targetWidth), ofDividerAt: 0)
                }
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: Store

    private var collapsed: Bool { store.sidebarCollapsed }

    var body: some View {
        List {
            if collapsed {
                collapseRailButton
                ForEach(store.files) { file in
                    fileButton(file)
                }
            } else {
                Section(L10n.text("Configurations")) {
                    ForEach(store.files) { file in
                        fileButton(file)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { if !collapsed { bottomBar } }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            if !collapsed {
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.createEmptyFile()
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .help(L10n.text("Create empty file"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addFile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.text("Add existing file…"))
                }
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.setSidebarCollapsed(true)
                    } label: {
                        Image(systemName: "sidebar.squares.left")
                    }
                    .help(L10n.text("Collapse sidebar"))
                }
            }
        }
    }

    private var collapseRailButton: some View {
        Button {
            store.setSidebarCollapsed(false)
        } label: {
            Image(systemName: "sidebar.squares.left")
                .font(.system(size: 17))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .help(L10n.text("Expand sidebar"))
    }

    /// Eine klickbare Zeile (voll oder nur Symbol) mit Kontextmenü.
    @ViewBuilder
    private func fileButton(_ file: ConfigFile) -> some View {
        Button {
            store.selectFromSidebar(file.id)
        } label: {
            if collapsed {
                CollapsedFileRow(file: file)
            } else {
                FileRow(file: file)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground(for: file))
        .help(collapsed ? file.displayName : "")
        // Picker als Popover an der Zeile: eigenes Fenster (kein Editor-I-Beam)
        // und schließt automatisch bei Klick daneben.
        .popover(item: pickerBinding(for: file), arrowEdge: .trailing) { target in
            SymbolPickerSheet(file: target)
                .environmentObject(store)
                .frame(width: 430, height: 430)
        }
        .contextMenu {
            Button { promptRename(file) } label: {
                Label(L10n.text("Rename…"), systemImage: "pencil")
            }
            Button { store.symbolPickerTarget = file } label: {
                Label(L10n.text("Change icon & color…"), systemImage: "square.grid.2x2")
            }
            Divider()
            Button(role: .destructive) { store.removeFile(file) } label: {
                Label(L10n.text("Remove from list"), systemImage: "trash")
            }
        }
    }

    /// Popover nur an der Zeile öffnen, deren id dem Picker-Ziel entspricht.
    private func pickerBinding(for file: ConfigFile) -> Binding<ConfigFile?> {
        Binding(
            get: { store.symbolPickerTarget?.id == file.id ? store.symbolPickerTarget : nil },
            set: { store.symbolPickerTarget = $0 }
        )
    }

    private func rowBackground(for file: ConfigFile) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(store.selection == file.id ? Color.accentColor.opacity(0.22) : Color.clear)
            .padding(.horizontal, 4)
    }

    private var bottomBar: some View {
        Toggle(isOn: $store.autoBackup) {
            Label(L10n.text("Back up on save"), systemImage: "clock.arrow.circlepath")
                .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true          // Dotfiles wie .zshrc anzeigen
        panel.message = L10n.text("Choose configuration files")
        panel.prompt = L10n.text("Add")
        if panel.runModal() == .OK {
            for url in panel.urls {
                store.addFile(url: url)
            }
        }
    }

    /// Fragt per Dialog einen neuen Dateinamen ab und benennt die Datei um.
    private func promptRename(_ file: ConfigFile) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Rename")
        alert.informativeText = L10n.format("New filename for “%@”:", file.url.lastPathComponent)
        alert.addButton(withTitle: L10n.text("Rename"))
        alert.addButton(withTitle: L10n.text("Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = file.url.lastPathComponent
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            store.renameFile(file, to: field.stringValue)
        }
    }
}

// MARK: - Zeilen

struct FileRow: View {
    let file: ConfigFile
    @EnvironmentObject var store: Store

    var body: some View {
        // Basis: der Auswahl-Button (ganze Zeile). Die Aktions-Buttons liegen
        // als Overlay DARÜBER (Geschwister, nicht verschachtelt) – sonst
        // schluckt der äußere Button ihre Klicks.
        Button {
            store.selectFromSidebar(file.id)
        } label: {
            HStack(spacing: 10) {
                Color.clear.frame(width: 26, height: 26)   // Platz für Symbol-Button
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(file.displayName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if store.selection == file.id && store.hasUnsavedChanges {
                            Circle().fill(.orange).frame(width: 6, height: 6)
                        }
                    }
                    Text(file.exists ? file.subtitle : L10n.text("not found"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !file.exists {
                    Image(systemName: "plus.circle.dashed")
                        .foregroundStyle(.tertiary)
                }
                Color.clear.frame(width: 26, height: 26)   // Platz für Trash-Button
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .opacity(file.exists ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) { symbolButton }
        .overlay(alignment: .trailing) { trashButton }
    }

    /// Öffnet den Symbol-Picker (Hover hebt das Icon hervor).
    private var symbolButton: some View {
        Hoverable { hovering in
            Button { store.symbolPickerTarget = file } label: {
                Image(systemName: file.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(file.symbolColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hovering ? Color.primary.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(L10n.text("Change icon & color…"))
        }
    }

    /// Entfernt den Eintrag; wird beim Überfahren rot.
    private var trashButton: some View {
        Hoverable { hovering in
            Button { store.removeFile(file) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(hovering ? Color.red : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hovering ? Color.red.opacity(0.15) : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(L10n.text("Remove from list"))
        }
    }
}

/// Eingeklappte Darstellung: nur das Symbol, zentriert.
struct CollapsedFileRow: View {
    let file: ConfigFile

    var body: some View {
        Image(systemName: file.symbol)
            .font(.system(size: 17))
            .foregroundStyle(file.symbolColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(file.exists ? 1 : 0.55)
    }
}

// MARK: - Symbol-Picker

struct SymbolPickerSheet: View {
    @EnvironmentObject var store: Store
    let file: ConfigFile

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    /// Aktueller Stand live aus dem Store (für Markierung & Vorschau).
    private var current: ConfigFile {
        store.files.first(where: { $0.id == file.id }) ?? file
    }
    private var currentColor: Color { current.symbolColor }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Live-Vorschau des aktuellen Symbols + Farbe.
                Image(systemName: current.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(currentColor)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(currentColor.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text("Icon & color"))
                        .font(.subheadline).bold()
                    Text(file.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(L10n.text("Done")) { store.symbolPickerTarget = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        colorDot(hex: nil)   // Standard (Sprachfarbe)
                        ForEach(Store.colorChoices, id: \.self) { hex in
                            colorDot(hex: hex)
                        }
                    }

                    Divider()

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Store.symbolChoices, id: \.self) { sym in
                            symbolCell(sym)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    /// Farb-Swatch; `hex == nil` ist die Standard-Sprachfarbe.
    @ViewBuilder
    private func colorDot(hex: String?) -> some View {
        let color = hex.flatMap { Color(hex: $0) } ?? file.language.accent
        let selected = current.colorHex == hex
        Hoverable { hovering in
            Button {
                store.setColor(file, to: hex)
            } label: {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 19, height: 19)
                    if hex == nil {
                        // Standard-Marker
                        Image(systemName: "a.circle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(2)
                .overlay(
                    Circle().strokeBorder(
                        selected ? Color.primary.opacity(0.6)
                                 : (hovering ? Color.primary.opacity(0.25) : .clear),
                        lineWidth: 2))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(hex == nil ? L10n.text("Default color") : "#\(hex!)")
        }
    }

    @ViewBuilder
    private func symbolCell(_ sym: String) -> some View {
        let selected = current.symbol == sym
        Hoverable { hovering in
            Button {
                store.setSymbol(file, to: sym)   // Live-Vorschau in der Sidebar
            } label: {
                Image(systemName: sym)
                    .font(.system(size: 18))
                    // Alle Symbole in der aktuell gewählten Farbe zeigen –
                    // so sieht man, wie jedes Symbol in dieser Farbe wirkt.
                    .foregroundStyle(currentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(selected ? currentColor.opacity(0.18)
                                  : (hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(selected ? currentColor : .clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .handCursor()
            .help(sym)
        }
    }
}
