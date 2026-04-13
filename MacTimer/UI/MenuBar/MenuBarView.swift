import SwiftUI
import CoreData

struct MenuBarView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var scheduler: SchedulerService
    @EnvironmentObject private var discovery: SystemTaskDiscoveryService

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TaskItem.nextRunAt, ascending: true)],
        predicate: NSPredicate(format: "isEnabled == YES"),
        animation: .default
    ) private var enabledTasks: FetchedResults<TaskItem>

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "isEnabled == NO"),
        animation: .default
    ) private var disabledTasks: FetchedResults<TaskItem>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stats
            statsSection

            Divider()

            // Upcoming tasks
            upcomingSection

            Divider()

            // Actions
            actionsSection
        }
        .padding(12)
        .frame(width: 280)
    }

    private var statsSection: some View {
        HStack(spacing: 16) {
            statItem(label: "运行中", value: enabledTasks.count, color: .green)
            statItem(label: "已暂停", value: disabledTasks.count, color: .secondary)
            statItem(label: "系统任务", value: discovery.tasks.count, color: .orange)
            statItem(label: "今日待执行", value: todayPendingCount, color: .blue)
        }
    }

    private func statItem(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("即将执行")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if enabledTasks.isEmpty {
                Text("暂无任务")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(upcomingTasks, id: \.id) { task in
                    upcomingRow(task: task)
                }
            }
        }
    }

    private func upcomingRow(task: TaskItem) -> some View {
        HStack {
            Image(systemName: task.taskType.iconName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(task.name)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            if let next = task.nextRunAt {
                Text(next, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        HStack {
            Button("打开主窗口") {
                openMainWindow()
            }
            .buttonStyle(.bordered)
            Spacer()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var upcomingTasks: [TaskItem] {
        Array(enabledTasks.prefix(5))
    }

    private var todayPendingCount: Int {
        let cal = Calendar.current
        let endOfDay = cal.startOfDay(for: Date()).addingTimeInterval(86400)
        return enabledTasks.filter { task in
            guard let next = task.nextRunAt else { return false }
            return next <= endOfDay
        }.count
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Post notification so AppDelegate opens the window
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("com.mactimer.openMainWindow")
}
