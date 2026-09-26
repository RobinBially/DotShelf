import SwiftUI
import AppKit

/// Dialog für den auszuführenden Befehl – wie eine Run-Konfiguration in IntelliJ.
struct RunSheet: View {
    @EnvironmentObject var store: Store
    @State private var draft: RunConfiguration

    init(configuration: RunConfiguration) {
        _draft = State(initialValue: configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text(L10n.text("Run a command"))
                    .font(.headline)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel(L10n.text("Command"))
                    TextField(L10n.text("e.g. docker compose up"), text: $draft.command, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1...5)
                        .frame(minWidth: 380)
                }
                GridRow {
                    fieldLabel(L10n.text("Working directory"))
                    HStack(spacing: 8) {
                        TextField("", text: workingDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button(L10n.text("Choose…")) { chooseDirectory() }
                    }
                }
                GridRow {
                    fieldLabel(L10n.text("Name"))
                    TextField(L10n.text("Optional name"), text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(L10n.text("The command runs in a login shell. The output appears in a new terminal entry in the sidebar."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(L10n.text("Cancel")) { store.runDraft = nil }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("Run")) {
                    if store.run(draft) != nil { store.runDraft = nil }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private var workingDirectoryPath: Binding<String> {
        Binding(
            get: { (draft.workingDirectory.path as NSString).abbreviatingWithTildeInPath },
            set: {
                var updated = draft
                updated.workingDirectory =
                    URL(fileURLWithPath: (($0 as NSString).expandingTildeInPath))
                draft = updated
            })
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = draft.workingDirectory
        panel.message = L10n.text("Choose the working directory")
        panel.prompt = L10n.text("Choose")
        if panel.runModal() == .OK, let url = panel.url {
            var updated = draft
            updated.workingDirectory = url
            draft = updated
        }
    }
}
