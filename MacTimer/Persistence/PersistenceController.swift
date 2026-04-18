import CoreData
import AppKit

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let context = result.container.viewContext
        // Insert sample TaskItem for previews
        let task = TaskItem(context: context)
        task.id = UUID()
        task.name = "早晨提醒"
        task.isEnabled = true
        task.taskTypeRaw = TaskType.notification.rawValue
        task.payload = TaskPayload(notificationTitle: "早晨提醒", notificationBody: "该起床了！")
        task.schedule = ScheduleConfig(
            type: .fixedTime,
            fixedTime: FixedTimeConfig(weekdays: [1, 2, 3, 4, 5], hour: 9, minute: 0),
            once: nil,
            interval: nil
        )
        task.createdAt = Date()
        try? context.save()
        return result
    }()

    let container: NSPersistentContainer

    /// Indicates whether the persistent store failed to load and the app is non-functional.
    let storeLoadFailed: Bool

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MacTimer")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        let storeURL = container.persistentStoreDescriptions.first?.url
        let theContainer = container

        var loadFailed = false
        var didResetData = false
        var retryFailureError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        container.loadPersistentStores { description, error in
            if let error = error {
                NSLog("CoreData: failed to load persistent store: \(error)")
                // Attempt recovery by removing the corrupted store and reloading
                if let storeURL = storeURL {
                    PersistenceController.backupStoreFiles(at: storeURL)
                    PersistenceController.removeStoreFiles(at: storeURL)
                }

                // Remove any existing stores from the coordinator before retrying
                for store in theContainer.persistentStoreCoordinator.persistentStores {
                    try? theContainer.persistentStoreCoordinator.remove(store)
                }

                let retrySemaphore = DispatchSemaphore(value: 0)
                theContainer.loadPersistentStores { _, retryError in
                    if let retryError = retryError {
                        NSLog("CoreData: failed to load persistent store after reset: \(retryError)")
                        loadFailed = true
                        retryFailureError = retryError
                    } else {
                        NSLog("CoreData: successfully recreated persistent store after removing corrupted data")
                        didResetData = true
                    }
                    retrySemaphore.signal()
                }
                retrySemaphore.wait()
            }
            semaphore.signal()
        }
        semaphore.wait()

        // Show alerts after semaphores are released to avoid deadlocking the main thread
        if let retryError = retryFailureError {
            PersistenceController.showStoreResetFailureAlert(error: retryError)
        } else if didResetData {
            PersistenceController.showDataResetAlert()
        }

        storeLoadFailed = loadFailed
        if !loadFailed {
            container.viewContext.automaticallyMergesChangesFromParent = true
        }
    }

    /// Back up the SQLite store file and its companion files before deletion.
    private static func backupStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        let suffixes = ["", "-shm", "-wal"]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        for suffix in suffixes {
            let sourceURL = URL(fileURLWithPath: url.path + suffix)
            let backupURL = URL(fileURLWithPath: url.path + suffix + ".backup-\(timestamp)")
            if fileManager.fileExists(atPath: sourceURL.path) {
                do {
                    try fileManager.copyItem(at: sourceURL, to: backupURL)
                    NSLog("CoreData: backed up \(sourceURL.lastPathComponent) to \(backupURL.lastPathComponent)")
                } catch {
                    NSLog("CoreData: failed to back up \(sourceURL.lastPathComponent): \(error)")
                }
            }
        }
    }

    /// Remove the SQLite store file and its companion files (-shm, -wal).
    private static func removeStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        let suffixes = ["", "-shm", "-wal"]
        for suffix in suffixes {
            let fileURL = URL(fileURLWithPath: url.path + suffix)
            try? fileManager.removeItem(at: fileURL)
        }
    }

    /// Inform the user that corrupted data was detected and has been reset.
    private static func showDataResetAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "数据已重置"
            alert.informativeText = "MacTimer 检测到数据文件损坏，已自动重置数据。损坏的数据文件已备份至应用数据目录（文件名含 .backup-）。之前的任务配置需要重新配置。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    /// Inform the user that the store could not be recovered at all.
    private static func showStoreResetFailureAlert(error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "数据加载失败"
            alert.informativeText = "MacTimer 无法加载或恢复数据文件，应用功能可能受限。请尝试重新启动应用，或联系支持。\n\n错误信息：\(error.localizedDescription)"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}
