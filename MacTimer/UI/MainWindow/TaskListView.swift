import SwiftUI
import CoreData

struct TaskListView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var scheduler: SchedulerService
    @EnvironmentObject private var discovery: SystemTaskDiscoveryService

    let onEdit: (TaskItem) -> Void

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TaskItem.createdAt, ascending: false)],
        animation: .default
    ) private var tasks: FetchedResults<TaskItem>

    @State private var selection: Set<UUID> = []
    @State private var loggingTask: TaskItem?
    @State private var inspectingSystemTask: SystemTask?
    /// 自增 ID，用于强制 Table 在 CoreData 变更后重新渲染
    @State private var refreshID = UUID()

    var body: some View {
        VSplitView {
            // MARK: 用户任务
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title: "我的任务", count: tasks.count, icon: "tray.full")
                userTaskTable
            }

            // MARK: 系统任务
            VStack(alignment: .leading, spacing: 0) {
                systemTaskHeader
                systemTaskTable
            }
            .frame(minHeight: 120)
        }
        .sheet(item: $loggingTask) { task in
            ExecutionLogView(taskID: task.id, taskName: task.name)
                .environment(\.managedObjectContext, context)
        }
        .sheet(item: $inspectingSystemTask) { sysTask in
            SystemTaskDetailView(task: sysTask)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            refreshID = UUID()
        }
    }

    // MARK: - 用户任务 Table

    private var userTaskTable: some View {
        Table(tasks, selection: $selection) {
            TableColumn("名称") { task in
                HStack(spacing: 6) {
                    Image(systemName: task.taskType.iconName)
                        .foregroundStyle(Color.accentColor)
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
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let task = tasks.first(where: { $0.id == id }) {
                Button("编辑") { onEdit(task) }
                Divider()
                Button("删除", role: .destructive) { deleteTask(task) }
            }
        }
        .id(refreshID)
    }

    // MARK: - 系统任务 Table

    private var systemTaskHeader: some View {
        HStack {
            sectionHeader(
                title: "系统任务",
                count: discovery.tasks.count,
                icon: "lock.shield"
            )
            Spacer()
            if let date = discovery.lastDiscoveryDate {
                Text("上次扫描: \(date, style: .relative)前")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Button {
                discovery.discover()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("重新扫描系统任务")
            .padding(.trailing, 8)
        }
    }

    private var systemTaskTable: some View {
        Table(discovery.tasks) {
            TableColumn("名称") { task in
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: task.source.iconName)
                        .foregroundStyle(sourceColor(task.source))
                    Text(task.name)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("来源") { task in
                Text(task.source.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sourceColor(task.source).opacity(0.15))
                    .cornerRadius(4)
            }
            .width(80)

            TableColumn("执行时间") { task in
                Text(task.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("命令") { task in
                Text(task.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(task.command)
            }
            .width(min: 100, ideal: 160)

            TableColumn("状态") { task in
                HStack(spacing: 4) {
                    Circle()
                        .fill(task.isLoaded ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(task.isLoaded ? "运行中" : "未加载")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(70)

            TableColumn("操作") { task in
                Button {
                    inspectingSystemTask = task
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("查看原始内容")
            }
            .width(50)
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeader(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption.bold())
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func sourceColor(_ source: SystemTaskSource) -> Color {
        switch source {
        case .launchd:  return .orange
        case .crontab:  return .purple
        }
    }

    private func showLog(_ task: TaskItem) {
        loggingTask = task
    }

    private func deleteTask(_ task: TaskItem) {
        task.isEnabled = false
        scheduler.reschedule(task: task)

        // Clean up orphaned ExecutionLogItem records linked by taskID
        let logRequest = ExecutionLogItem.fetchRequest()
        logRequest.predicate = NSPredicate(format: "taskID == %@", task.id as CVarArg)
        if let logs = try? context.fetch(logRequest) {
            for log in logs {
                context.delete(log)
            }
        }

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

// MARK: - 系统任务详情弹窗

struct SystemTaskDetailView: View {
    let task: SystemTask
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: task.source.iconName)
                    .font(.title2)
                    .foregroundStyle(task.source == .launchd ? .orange : .purple)
                VStack(alignment: .leading) {
                    Text(task.name)
                        .font(.headline)
                    Text(task.source.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(task.isLoaded ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(task.isLoaded ? "运行中" : "未加载")
                        .font(.caption)
                }
            }

            Divider()

            // 调度信息
            LabeledContent("执行时间") {
                Text(task.scheduleDescription)
            }

            // 命令
            LabeledContent("命令") {
                Text(task.command)
                    .textSelection(.enabled)
            }

            Divider()

            // 原始内容
            VStack(alignment: .leading, spacing: 4) {
                Text("原始内容")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(task.rawContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            }

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, maxWidth: 560, minHeight: 400)
    }
}
