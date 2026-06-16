import SwiftUI

struct DetailView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let file = store.selectedFile {
            VStack(spacing: 0) {
                CodeEditor(text: $store.text, language: file.language, fontSize: store.fontSize)
                    .id(file.id)
                Divider()
                statusBar(file)
            }
            .navigationTitle(file.displayName)
            .navigationSubtitle(file.prettyPath)
            .toolbar { toolbarContent(file) }
        } else {
            ContentUnavailableView(
                "Keine Datei ausgewählt",
                systemImage: "doc.text",
                description: Text("Wähle links eine Konfigurationsdatei."))
        }
    }

    private func languageBadge(_ lang: ConfigLanguage) -> some View {
        Text(lang.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(lang.accent.opacity(0.15), in: Capsule())
            .foregroundStyle(lang.accent)
    }

    // MARK: - Statuszeile

    private func statusBar(_ file: ConfigFile) -> some View {
        HStack(spacing: 12) {
            validationView
            if let err = store.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if !store.statusMessage.isEmpty {
                Text(store.statusMessage)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.hasUnsavedChanges {
                Label("Ungespeichert", systemImage: "pencil.circle.fill")
                    .foregroundStyle(.orange)
            }
            Text("\(lineCount) Zeilen")
                .foregroundStyle(.tertiary)
            zoomControl
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var zoomControl: some View {
        HStack(spacing: 2) {
            Button { store.zoomOut() } label: { Image(systemName: "minus") }
                .help("Kleiner (⌘-)")
            Text("\(Int(store.fontSize)) pt")
                .foregroundStyle(.secondary)
                .frame(width: 34)
                .monospacedDigit()
            Button { store.zoomIn() } label: { Image(systemName: "plus") }
                .help("Größer (⌘+)")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    @ViewBuilder
    private var validationView: some View {
        switch store.validation {
        case .notApplicable:
            EmptyView()
        case .valid:
            Label("JSON gültig", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .invalid(let msg):
            Label("JSON ungültig: \(msg)", systemImage: "xmark.seal.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
                .help(msg)
        }
    }

    private var lineCount: Int {
        max(1, store.text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } })
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(_ file: ConfigFile) -> some ToolbarContent {
        // Badge ohne eigene Glas-Pille (auf macOS 26 den Shared-Background ausblenden).
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .automatic) {
                languageBadge(file.language)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .automatic) {
                languageBadge(file.language)
            }
        }

        ToolbarItemGroup(placement: .automatic) {
            Button {
                store.reload()
            } label: {
                Label("Neu laden", systemImage: "arrow.clockwise")
            }
            .help("Vom Datenträger neu laden (verwirft Änderungen)")

            if file.language.isJSONLike {
                Button {
                    store.formatJSON()
                } label: {
                    Label("Formatieren", systemImage: "wand.and.stars")
                }
                .help("JSON hübsch formatieren")
            }

            Button {
                store.revealInFinder()
            } label: {
                Label("Im Finder", systemImage: "folder")
            }
            .help("Im Finder anzeigen")

            Button {
                store.save()
            } label: {
                Label("Speichern", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!store.hasUnsavedChanges)
            .help("Speichern (⌘S)")
        }
    }
}
