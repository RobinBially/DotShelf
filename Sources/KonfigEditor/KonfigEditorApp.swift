import SwiftUI
import AppKit

@main
struct DotShelfApp: App {
    @StateObject private var store = Store()
    @NSApplicationDelegateAdaptor(DotShelfAppDelegate.self) private var appDelegate

    private var startSize: CGSize {
        let frame = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: frame.width * 0.8, height: frame.height * 0.8)
    }

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
        .defaultSize(width: startSize.width, height: startSize.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button(L10n.text("Save")) { store.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.hasUnsavedChanges)
                Button(L10n.text("Reload")) { store.reload() }
                    .keyboardShortcut("r", modifiers: .command)
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
        confirmExit() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
