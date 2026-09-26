import SwiftUI
import AppKit

@main
struct DotShelfApp: App {
    @StateObject private var store = Store()
    @NSApplicationDelegateAdaptor(DotShelfAppDelegate.self) private var appDelegate

    var body: some Scene {
        // One shared editor buffer needs exactly one document window.
        Window("DotShelf", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(appDelegate)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear { appDelegate.store = store }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        // Erster Start: angenehme Größe in der Bildschirmmitte. Danach merkt
        // sich macOS die Größe, die der Nutzer eingestellt hat.
        .defaultSize(width: WindowGeometry.startSize.width,
                     height: WindowGeometry.startSize.height)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button(L10n.text("Save")) { store.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.hasUnsavedChanges)
                Button(L10n.text("Reload")) { store.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.selectedTerminal != nil)
            }
            CommandGroup(after: .saveItem) {
                Button(L10n.text("Run")) { store.runSelectedFile() }
                    .keyboardShortcut("r", modifiers: .control)
                Button(L10n.text("Run with Options…")) { store.presentRunSheet(for: store.selectedFile) }
                    .keyboardShortcut("r", modifiers: [.control, .option])
                Button(L10n.text("Open Terminal")) { store.openTerminal() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Divider()
                Button(L10n.text("Rerun")) { store.rerunSelectedSession() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!(store.selectedTerminal.map { !$0.isRunning } ?? false))
                Button(L10n.text("Stop")) { store.stopSelectedSession() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!(store.selectedTerminal?.isRunning ?? false))
                Button(L10n.text("Clear Terminal")) { store.clearSelectedSession() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(store.selectedTerminal == nil)
            }
            CommandGroup(after: .toolbar) {
                Button(L10n.text("Zoom In")) { store.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button(L10n.text("Zoom Out")) { store.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button(L10n.text("Actual Size")) { store.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}

@MainActor
final class DotShelfAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    weak var store: Store?
    private var exitApproved = false
    private var isConfirmingExit = false

    /// Window close and Quit share one decision. An approved close terminates
    /// this single-window app, so applicationShouldTerminate must not ask again.
    func confirmExit() -> Bool {
        if exitApproved { return true }
        guard !isConfirmingExit else { return false }
        isConfirmingExit = true
        defer { isConfirmingExit = false }
        let approved = store?.confirmPendingChanges() ?? true
        exitApproved = approved
        return approved
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard confirmExit() else { return .terminateCancel }
        store?.stopAllSessions()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
