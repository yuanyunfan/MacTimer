import SwiftUI
import CoreData

struct TaskListView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var scheduler: SchedulerService

    let onEdit: (TaskItem) -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TaskItem.createdAt, ascending: false)],
        animation: .default
    ) private var tasks: FetchedResults<TaskItem>

    @State private var selection: Set<TaskItem> = [] // for future batch operations
    @State private var loggingTask: TaskItem?

    var body: some View {
        Table(tasks, selection: $selection) {
            TableColumn("名称") { task in
                HStack(spacing: 6) {
                    Image(systemName: task.taskType.iconName)
                        .foregroundStyle(.accent)
                    Text(task.name)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("类型") { task in
                Text(task.taskType.displayName)
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("执行时间") { task in
                Text(scheduleDescription(task.schedule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("下次执行") { task in
                if let next = task.nextRunAt {
                    Text(next, style: .relative)
                        .font(.caption)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(90)

            TableColumn("上次执行") { task in
                if let last = task.lastRunAt {
                    Text(last, style: .relative)
                        .font(.caption)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(90)

            TableColumn("状态") { task in
                Toggle("", isOn: Binding(
                    get: { task.isEnabled },
                    set: { newValue in
                        task.isEnabled = newValue
                        scheduler.reschedule(task: task)
                        try? context.save()
                    }
                ))
                .labelsHidden()
            }
            .width(50)

            TableColumn("操作") { task in
                HStack(spacing: 4) {
                    Button("编辑") { onEdit(task) }
                        .buttonStyle(.borderless)
                    Button {
                        showLog(task)
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        deleteTask(task)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .width(90)
        }
        .contextMenu(forSelectionType: TaskItem.self) { items in
            if let task = items.first {
                Button("编辑") { onEdit(task) }
                Divider()
                Button("删除", role: .destructive) { deleteTask(task) }
            }
        }
        .sheet(item: $loggingTask) { task in
            ExecutionLogView(taskID: task.id, taskName: task.name)
                .environment(\.managedObjectContext, context)
        }
    }   // end of `var body`

    private func showLog(_ task: TaskItem) {
        loggingTask = task
    }

    private func deleteTask(_ task: TaskItem) {
        task.isEnabled = false
        scheduler.reschedule(task: task) // isEnabled=false → cancels timer without re-scheduling
        context.delete(task)
        try? context.save()
    }

    private func scheduleDescription(_ schedule: ScheduleConfig) -> String {
        switch schedule.type {
        case .interval:
            guard let cfg = schedule.interval else { return "—" }
            let hours = cfg.seconds / 3600
            let minutes = (cfg.seconds % 3600) / 60
            if hours > 0 && minutes > 0 { return "每 \(hours) 小时 \(minutes) 分" }
            if hours > 0 { return "每 \(hours) 小时" }
            return "每 \(minutes) 分钟"
        case .fixedTime:
            guard let cfg = schedule.fixedTime else { return "—" }
            let days = cfg.weekdays.map { weekdayName($0) }.joined(separator: "、")
            return "\(days) \(String(format: "%02d:%02d", cfg.hour, cfg.minute))"
        }
    }

    private func weekdayName(_ iso: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][safe: iso - 1] ?? "?"
    }
}

