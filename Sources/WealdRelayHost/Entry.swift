import AppKit
import SwiftUI
import Observation

/// A status item, a popover, and nothing else. No dock tile, no window, no menu
/// bar menus: the panel is the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let host = RelayHost()
    private var item: NSStatusItem!
    private var popover: NSPopover!
    private var watch: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarMark.image()
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Weald Relay Host"

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: PanelView(host: host, onQuit: { NSApp.terminate(nil) })
        )

        host.begin()
        trackPhase()
    }

    /// The icon dims when nothing is serving, so the state is legible without a
    /// click. Observation is re-armed after every read, which is how the
    /// framework's one-shot tracking is turned into a subscription.
    private func trackPhase() {
        withObservationTracking {
            _ = host.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.item.button?.alphaValue = self.host.phase == .running ? 1.0 : 0.5
                self.trackPhase()
            }
        }
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        Task { await host.refresh() }
        if host.publicIP == nil { Task { await host.loadPublicIP() } }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        host.end()
    }
}

/// The mark in the menu bar, drawn rather than shipped as an asset so it stays
/// crisp at every scale and needs no bundle resource.
enum MenuBarMark {
    static func image() -> NSImage {
        let size = NSSize(width: 17, height: 15)
        let image = NSImage(size: size, flipped: false) { rect in
            let w = NSAttributedString(
                string: "W",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: NSColor.black,
                    .kern: -0.5
                ]
            )
            let bounds = w.size()
            w.draw(at: NSPoint(
                x: (rect.width - bounds.width) / 2,
                y: (rect.height - bounds.height) / 2
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}

@main
@MainActor
enum Entry {
    /// A hand-rolled entry point rather than `App`/`MenuBarExtra`, because the
    /// popover has to be dismissible and re-anchorable in ways the SwiftUI
    /// scene does not expose.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
