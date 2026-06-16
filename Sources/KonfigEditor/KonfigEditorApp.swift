import SwiftUI

@main
struct KonfigEditorApp: App {
    @StateObject private var store = Store()

    /// ~80 % der sichtbaren Bildschirmfläche als Startgröße.
    private var startSize: CGSize {
        let frame = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: frame.width * 0.8, height: frame.height * 0.8)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: startSize.width, height: startSize.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Speichern") { store.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.hasUnsavedChanges)
                Button("Neu laden") { store.reload() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            // Zoom – ⌘+, ⌘-, ⌘0 (auf deutscher Tastatur direkt erreichbar)
            CommandGroup(after: .toolbar) {
                Button("Größer") { store.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Kleiner") { store.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Originalgröße") { store.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}
