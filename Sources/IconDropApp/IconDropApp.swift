import AppKit
import SwiftUI

final class IconDropApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct IconDropApp: App {
    @NSApplicationDelegateAdaptor(IconDropApplicationDelegate.self) private var appDelegate
    @StateObject private var model = IconDropViewModel()

    var body: some Scene {
        Window("IconDrop", id: "main") {
            IconDropPanel(model: model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("IconDrop", systemImage: "folder.badge.gearshape") {
            IconDropPanel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
