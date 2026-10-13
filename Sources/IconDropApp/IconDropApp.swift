import AppKit
import SwiftUI

@MainActor
final class IconDropApplicationDelegate: NSObject, NSApplicationDelegate {
    private let model = IconDropViewModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        let icon = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "IconDrop")
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = "IconDrop"
        button.target = self
        button.action = #selector(togglePanel)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 520, height: 600)
        popover.contentViewController = NSHostingController(rootView: IconDropPanel(model: model))
        statusItem = item
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct IconDropApp: App {
    @NSApplicationDelegateAdaptor(IconDropApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
