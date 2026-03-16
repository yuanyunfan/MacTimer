import Foundation
import CoreData

@MainActor
final class SchedulerService: ObservableObject {
    static let shared = SchedulerService(context: PersistenceController.shared.container.viewContext)

    private let context: NSManagedObjectContext
    /// taskID → Timer
    private(set) var activeTimers: [UUID: Timer] = [:]

    /// Published so MenuBarView can observe failure state
    @Published var lastFailedTaskName: String?

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func start() {
        let request = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "isEnabled == YES")
        let tasks = (try? context.fetch(request)) ?? []
        for task in tasks {
            schedule(task: task, isFirstRun: true)
        }
    }

    func stop() {
        activeTimers.values.forEach { $0.invalidate() }
        activeTimers.removeAll()
    }

    func reschedule(task: TaskItem) {
        guard !task.isDeleted, !task.isFault else { return }
        cancelTimer(for: task.id)
        if task.isEnabled {
            schedule(task: task, isFirstRun: false)
        }
    }

    // MARK: Private

    private func schedule(task: TaskItem, isFirstRun: Bool) {
        guard let fireDate = ScheduleCalculator.nextRunAt(
            schedule: task.schedule,
            after: Date(),
            isFirstRun: isFirstRun
        ) else { return }

        task.nextRunAt = fireDate
        saveContext()

        let timer = Timer(fireAt: fireDate, interval: 0, target: self,
                          selector: #selector(timerFired(_:)), userInfo: task.id, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        activeTimers[task.id] = timer
    }

    @objc private func timerFired(_ timer: Timer) {
        guard let taskID = timer.userInfo as? UUID else { return }
        activeTimers.removeValue(forKey: taskID)

        let request = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
        guard let task = (try? context.fetch(request))?.first,
              task.isEnabled else { return }

        // SchedulerService is @MainActor, so the Task body already runs on the main actor.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await TaskExecutor.shared.execute(task: task, taskName: task.name)
            // Guard against use-after-free: the task could have been deleted
            // during the await gap above.
            guard !task.isDeleted, !task.isFault else { return }
            self.recordLog(task: task, outcome: outcome)
            task.lastRunAt = Date()
            if outcome.result != .success {
                self.lastFailedTaskName = task.name
                await NotificationService.shared.sendError(
                    taskName: task.name,
                    message: outcome.errorMessage ?? "未知错误"
                )
            }
            // Re-schedule for next run
            self.schedule(task: task, isFirstRun: false)
            self.saveContext()
        }
    }

    private func recordLog(task: TaskItem, outcome: ExecutionOutcome) {
        // Trim logs if over 200
        let trimRequest = ExecutionLogItem.fetchRequest()
        trimRequest.predicate = NSPredicate(format: "taskID == %@", task.id as CVarArg)
        trimRequest.sortDescriptors = [NSSortDescriptor(key: "executedAt", ascending: true)]
        let existing = (try? context.fetch(trimRequest)) ?? []
        if existing.count >= 200 {
            let toDelete = existing.prefix(existing.count - 199)
            toDelete.forEach { context.delete($0) }
        }

        let log = ExecutionLogItem(context: context)
        log.id = UUID()
        log.taskID = task.id
        log.executedAt = Date()
        log.result = outcome.result
        log.errorMessage = outcome.errorMessage
        log.duration = outcome.duration
    }

    private func cancelTimer(for taskID: UUID) {
        activeTimers[taskID]?.invalidate()
        activeTimers.removeValue(forKey: taskID)
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("[SchedulerService] Failed to save context: \(error)")
        }
    }

    #if DEBUG
    /// Test helper: directly set lastFailedTaskName to exercise the failure UI path.
    func simulateFailure(taskName: String) {
        lastFailedTaskName = taskName
    }
    #endif
}
