import SwiftUI
import AppKit

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
                let visible = screen.visibleFrame
                let width = visible.width * 0.8
                let height = visible.height * 0.8
                let x = visible.minX + (visible.width - width) / 2
                let y = visible.minY + (visible.height - height) / 2
                window.setFrame(NSRect(x: x, y: y, width: width, height: height),
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
