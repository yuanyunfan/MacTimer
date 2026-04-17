import Foundation
import CoreData
import AppKit

@MainActor
final class SchedulerService: ObservableObject {
    static let shared = SchedulerService(context: PersistenceController.shared.container.viewContext)

    private let context: NSManagedObjectContext
    /// taskID → Timer
    private(set) var activeTimers: [UUID: Timer] = [:]

    /// Published so MenuBarView can observe failure state
    @Published var lastFailedTaskName: String?

    /// Tracks whether sleep/wake observers have been registered
    private var observingSleepWake = false
    private var sleepWakeObserver: NSObjectProtocol?

    /// Tracks task IDs currently being executed to prevent duplicate execution
    /// (e.g. race between RunLoop-fired timer and wake handler)
    private var executingTaskIDs: Set<UUID> = []

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func start() {
        let request = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "isEnabled == YES")
        let tasks = (try? context.fetch(request)) ?? []
        let now = Date()
        for task in tasks {
            // Check if this task has a persisted nextRunAt that is in the past,
            // meaning it was missed (e.g. app was quit or machine was asleep).
            if let nextRunAt = task.nextRunAt, nextRunAt < now {
                handleMissedExecution(task: task, missedDate: nextRunAt)
            } else {
                schedule(task: task, isFirstRun: true)
            }
        }
        registerSleepWakeObservers()
    }

    deinit {
        if let observer = sleepWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
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

        let taskID = task.id
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTimerFired(taskID: taskID)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        activeTimers[task.id] = timer
    }

    private func handleTimerFired(taskID: UUID) {
        activeTimers.removeValue(forKey: taskID)

        // Guard against duplicate execution (e.g. wake handler already running this task)
        guard !executingTaskIDs.contains(taskID) else {
            print("[SchedulerService] Skipping timerFired for task \(taskID): already executing")
            return
        }

        let request = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
        guard let task = (try? context.fetch(request))?.first,
              task.isEnabled else { return }

        // 记录预定触发时间，用于计算下次执行（避免执行耗时累积导致漂移）
        let scheduledFireDate = task.nextRunAt ?? Date()

        executingTaskIDs.insert(taskID)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.executingTaskIDs.remove(taskID) }
            let outcome = await TaskExecutor.shared.execute(task: task, taskName: task.name)
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
            // 基于预定触发时间计算下次执行，防止时间漂移
            self.scheduleNext(task: task, afterFireDate: scheduledFireDate)
            self.saveContext()
        }
    }

    /// 基于上次预定触发时间计算下次执行，防止执行耗时导致时间漂移。
    /// 对于间隔任务：下次 = 上次预定时间 + 间隔（如果已过期则用当前时间兜底）
    /// 对于固定时间任务：直接用 ScheduleCalculator 从当前时间计算
    private func scheduleNext(task: TaskItem, afterFireDate: Date) {
        let now = Date()

        if task.schedule.type == .once {
            // 一次性任务执行后自动禁用，不再调度
            task.isEnabled = false
            task.nextRunAt = nil
            saveContext()
            return
        }

        if task.schedule.type == .interval, let cfg = task.schedule.interval {
            // 基于预定时间计算，避免漂移
            var nextFire = afterFireDate.addingTimeInterval(TimeInterval(cfg.seconds))
            // 如果计算出的时间已经过了（例如任务执行超过一个周期），用当前时间兜底
            if nextFire <= now {
                nextFire = now.addingTimeInterval(TimeInterval(cfg.seconds))
            }
            task.nextRunAt = nextFire
            saveContext()

            let taskID = task.id
            let timer = Timer(fire: nextFire, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleTimerFired(taskID: taskID)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            activeTimers[task.id] = timer
        } else {
            // 固定时间任务：基于预定触发时间计算下次执行，避免漂移
            guard let fireDate = ScheduleCalculator.nextRunAt(
                schedule: task.schedule,
                after: afterFireDate,
                isFirstRun: false
            ) else { return }

            // 如果计算出的时间已经过了，用当前时间重新计算
            let nextFire: Date
            if fireDate <= now {
                guard let fallback = ScheduleCalculator.nextRunAt(
                    schedule: task.schedule,
                    after: now,
                    isFirstRun: false
                ) else { return }
                nextFire = fallback
            } else {
                nextFire = fireDate
            }

            task.nextRunAt = nextFire
            saveContext()

            let taskID = task.id
            let timer = Timer(fire: nextFire, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleTimerFired(taskID: taskID)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            activeTimers[task.id] = timer
        }
    }

    // MARK: - Missed Execution Handling

    /// Handle a task whose nextRunAt is in the past (missed during sleep or app quit).
    /// Executes the task immediately and then schedules the next run.
    private func handleMissedExecution(task: TaskItem, missedDate: Date) {
        cancelTimer(for: task.id)

        // Guard against duplicate execution (e.g. RunLoop timer already running this task)
        guard !executingTaskIDs.contains(task.id) else {
            print("[SchedulerService] Skipping handleMissedExecution for '\(task.name)': already executing")
            return
        }

        print("[SchedulerService] Missed execution for '\(task.name)' (was due at \(missedDate)), executing now")

        let taskID = task.id
        executingTaskIDs.insert(taskID)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.executingTaskIDs.remove(taskID) }
            guard !task.isDeleted, !task.isFault, task.isEnabled else { return }

            let outcome = await TaskExecutor.shared.execute(task: task, taskName: task.name)
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

            // Schedule the next run from now
            self.scheduleNext(task: task, afterFireDate: Date())
            self.saveContext()
        }
    }

    // MARK: - Sleep / Wake

    private func registerSleepWakeObservers() {
        guard !observingSleepWake else { return }
        observingSleepWake = true

        let wsc = NSWorkspace.shared.notificationCenter
        sleepWakeObserver = wsc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDidWake()
            }
        }
    }

    private func handleDidWake() {
        // After waking from sleep, check all enabled tasks for missed executions.
        let request = TaskItem.fetchRequest()
        request.predicate = NSPredicate(format: "isEnabled == YES")
        let tasks = (try? context.fetch(request)) ?? []
        let now = Date()

        for task in tasks {
            if let nextRunAt = task.nextRunAt, nextRunAt < now {
                // Timer may have already fired (RunLoop fires expired timers on wake),
                // but if it was invalidated or lost, re-handle it.
                // Cancel any stale timer and handle the miss.
                handleMissedExecution(task: task, missedDate: nextRunAt)
            }
        }
    }

    // MARK: - Logging

    private func recordLog(task: TaskItem, outcome: ExecutionOutcome) {
        // Trim logs to keep at most 199 before inserting the new one (200 total after insert)
        let trimRequest = ExecutionLogItem.fetchRequest()
        trimRequest.predicate = NSPredicate(format: "taskID == %@", task.id as CVarArg)
        trimRequest.sortDescriptors = [NSSortDescriptor(key: "executedAt", ascending: true)]
        let existing = (try? context.fetch(trimRequest)) ?? []
        if existing.count >= 200 {
            let toDelete = existing.prefix(existing.count - 199)
            toDelete.forEach { context.delete($0) }
            // Save trim immediately so deletions are persisted even if a later save fails
            saveContext()
        }

        let log = ExecutionLogItem(context: context)
        log.id = UUID()
        log.taskID = task.id
        log.executedAt = Date()
        log.result = outcome.result
        log.errorMessage = outcome.errorMessage
        log.duration = outcome.duration

        // Save the new log entry immediately to prevent loss on later save failures
        saveContext()
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
