import AppKit
import SwiftUI
import Combine

final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupStatusItem()
        observeFailures()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "MacTimer")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environment(\.managedObjectContext,
                             PersistenceController.shared.container.viewContext)
                .environmentObject(SchedulerService.shared)
        )
        self.popover = popover
    }

    private func observeFailures() {
        SchedulerService.shared.$lastFailedTaskName
            .receive(on: RunLoop.main)
            .sink { [weak self] name in
                guard name != nil else { return }
                self?.flashRedIcon()
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func flashRedIcon() {
        statusItem?.button?.image = NSImage(systemSymbolName: "clock.badge.exclamationmark",
                                            accessibilityDescription: "MacTimer Error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.statusItem?.button?.image = NSImage(systemSymbolName: "clock",
                                                      accessibilityDescription: "MacTimer")
        }
    }
}
