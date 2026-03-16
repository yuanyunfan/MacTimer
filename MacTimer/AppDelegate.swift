import AppKit
import CoreData
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var mainWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        SchedulerService.shared.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openMainWindow),
            name: .openMainWindow,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @objc private func openMainWindow() {
        if mainWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MacTimer"
            window.center()
            window.contentViewController = NSHostingController(
                rootView: MainWindowView()
                    .environment(\.managedObjectContext,
                                 PersistenceController.shared.container.viewContext)
                    .environmentObject(SchedulerService.shared)
            )
            mainWindowController = NSWindowController(window: window)
        }
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

