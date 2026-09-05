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
                L10n.text("No file selected"),
                systemImage: "doc.text",
                description: Text(L10n.text("Choose a configuration file in the sidebar.")))
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
                Label(L10n.text("Unsaved"), systemImage: "pencil.circle.fill")
                    .foregroundStyle(.orange)
            }
            Text(lineCount == 1 ? L10n.text("1 line") : L10n.format("%d lines", lineCount))
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
                .help(L10n.text("Zoom out (⌘−)"))
            Text("\(Int(store.fontSize)) pt")
                .foregroundStyle(.secondary)
                .frame(width: 34)
                .monospacedDigit()
            Button { store.zoomIn() } label: { Image(systemName: "plus") }
                .help(L10n.text("Zoom in (⌘+)"))
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
            Label(L10n.text("Valid JSON"), systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .invalid(let msg):
            Label(L10n.format("Invalid JSON: %@", msg), systemImage: "xmark.seal.fill")
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
                Label(L10n.text("Reload"), systemImage: "arrow.clockwise")
            }
            .help(L10n.text("Reload from disk"))

            if file.language.isJSONLike {
                Button {
                    store.formatJSON()
                } label: {
                    Label(L10n.text("Format"), systemImage: "wand.and.stars")
                }
                .help(L10n.text("Format JSON"))
            }

            Button {
                store.revealInFinder()
            } label: {
                Label(L10n.text("Finder"), systemImage: "folder")
            }
            .help(L10n.text("Show in Finder"))

            Button {
                store.save()
            } label: {
                Label(L10n.text("Save"), systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!store.hasUnsavedChanges)
            .help(L10n.text("Save (⌘S)"))
        }
    }
}
