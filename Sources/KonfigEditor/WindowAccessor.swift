import SwiftUI
import AppKit

/// Greift auf das umgebende NSWindow zu und setzt es einmalig auf ~80 %
/// der sichtbaren Bildschirmfläche, zentriert.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window,
                  let screen = window.screen ?? NSScreen.main else { return }
            if context.coordinator.didConfigure { return }
            context.coordinator.didConfigure = true

            let visible = screen.visibleFrame
            let width = visible.width * 0.8
            let height = visible.height * 0.8
            let x = visible.minX + (visible.width - width) / 2
            let y = visible.minY + (visible.height - height) / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height),
                            display: true, animate: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didConfigure = false
    }
}
