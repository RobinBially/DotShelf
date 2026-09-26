import SwiftUI
import AppKit

/// Startgröße des Fensters – wie bei üblichen Mac-Apps: großzügig, aber nicht
/// bildschirmfüllend, damit Sidebar und Inhalt nebeneinander atmen können.
enum WindowGeometry {
    static var startSize: CGSize { startSize(for: NSScreen.main) }

    static func startSize(for screen: NSScreen?) -> CGSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size
            ?? CGSize(width: 1440, height: 900)
        return CGSize(width: max(820, min(visible.width * 0.7, 1280)),
                      height: max(520, min(visible.height * 0.78, 900)))
    }
}

/// Sets the initial window geometry and preserves SwiftUI's window delegate
/// while adding the unsaved-changes check for the close button and Command-W.
struct WindowConfigurator: NSViewRepresentable {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var appDelegate: DotShelfAppDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        appDelegate.store = store
        context.coordinator.configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configure(nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(appDelegate: appDelegate) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.restoreDelegate()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private let appDelegate: DotShelfAppDelegate
        private weak var window: NSWindow?
        private weak var forwardedDelegate: NSWindowDelegate?
        private var didConfigure = false

        init(appDelegate: DotShelfAppDelegate) {
            self.appDelegate = appDelegate
        }

        func configure(_ view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                if self.window !== window {
                    self.restoreDelegate()
                    self.window = window
                    self.didConfigure = false
                }
                if window.delegate !== self {
                    self.forwardedDelegate = window.delegate
                    window.delegate = self
                }
                guard !self.didConfigure,
                      let screen = window.screen ?? NSScreen.main else { return }
                self.didConfigure = true
                // Die zuletzt benutzte Größe bleibt stehen; macOS stellt sie
                // selbst wieder her. Nur ein Fenster, das nicht mehr auf den
                // Bildschirm passt (etwa nach einem Monitorwechsel), bekommt
                // die Startgröße zurück.
                let visible = screen.visibleFrame
                let fits = visible.width >= window.frame.width
                    && visible.height >= window.frame.height
                guard !fits || !visible.intersects(window.frame) else { return }
                let size = WindowGeometry.startSize(for: screen)
                window.setFrame(NSRect(x: visible.minX + (visible.width - size.width) / 2,
                                       y: visible.minY + (visible.height - size.height) / 2,
                                       width: size.width, height: size.height),
                                display: true, animate: false)
            }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // Preserve any veto from the original delegate before approving exit.
            guard forwardedDelegate?.windowShouldClose?(sender) ?? true else { return false }
            return appDelegate.confirmExit()
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || forwardedDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if forwardedDelegate?.responds(to: aSelector) == true {
                return forwardedDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }

        func restoreDelegate() {
            if let window, window.delegate === self {
                window.delegate = forwardedDelegate
            }
            window = nil
            forwardedDelegate = nil
        }
    }
}
