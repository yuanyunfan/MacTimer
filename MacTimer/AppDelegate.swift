import AppKit
import CoreData
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarController: MenuBarController?
    private var mainWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置通知代理，允许 app 前台时也显示通知横幅
        UNUserNotificationCenter.current().delegate = self
        menuBarController = MenuBarController()
        SchedulerService.shared.start()
        SystemTaskDiscoveryService.shared.discover()
        Task {
            await NotificationService.shared.requestPermission()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openMainWindow),
            name: .openMainWindow,
            object: nil
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 允许 app 在前台时也展示通知横幅和声音
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
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
                    .environmentObject(SystemTaskDiscoveryService.shared)
            )
            mainWindowController = NSWindowController(window: window)
        }
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

