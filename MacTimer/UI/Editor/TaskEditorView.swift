import SwiftUI
import CoreData

struct TaskEditorView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var scheduler: SchedulerService

    let task: TaskItem?        // nil = create new
    let onDismiss: () -> Void

    // Form state
    @State private var name: String = ""
    @State private var taskType: TaskType = .notification
    @State private var payload: TaskPayload = TaskPayload()
    @State private var schedule: ScheduleConfig = ScheduleConfig(
        type: .interval,
        fixedTime: FixedTimeConfig(weekdays: [1, 2, 3, 4, 5], hour: 9, minute: 0),
        interval: IntervalConfig(seconds: 3600, startImmediately: false)
    )
    @State private var validationError: String?

    var isCreating: Bool { task == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("任务名称", text: $name)
                    Picker("任务类型", selection: $taskType) {
                        ForEach(TaskType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ScheduleEditorSection(schedule: $schedule)

                PayloadEditorSection(taskType: $taskType, payload: $payload)

                if let error = validationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isCreating ? "新建任务" : "编辑任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 480)
        .onAppear { loadExisting() }
    }

    private func loadExisting() {
        guard let task else { return }
        name = task.name
        taskType = task.taskType
        payload = task.payload
        schedule = task.schedule
    }

    private func save() {
        // Validate
        if let error = validate() {
            validationError = error
            return
        }
        validationError = nil

        let item = task ?? TaskItem(context: context)
        if isCreating {
            item.id = UUID()
            item.createdAt = Date()
            item.isEnabled = true
        }
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.taskType = taskType
        item.payload = payload
        item.schedule = schedule

        do {
            try context.save()
            scheduler.reschedule(task: item)
            onDismiss()
        } catch {
            validationError = "保存失败：\(error.localizedDescription)"
        }
    }

    private func validate() -> String? {
        switch taskType {
        case .openURL:
            guard let urlStr = payload.urlString, !urlStr.isEmpty else {
                return "请输入 URL"
            }
            guard URL(string: urlStr) != nil && (urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://")) else {
                return "URL 格式不正确，请以 http:// 或 https:// 开头"
            }
        case .openApp:
            guard payload.bundleID != nil else {
                return "请选择要打开的 App"
            }
        case .shellScript:
            guard let cmd = payload.command, !cmd.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "请输入 Shell 命令"
            }
        case .notification:
            guard let title = payload.notificationTitle,
                  !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "请输入通知标题"
            }
        }
        if schedule.type == .interval {
            guard let cfg = schedule.interval, cfg.seconds >= 60 else {
                return "间隔时间最小为 60 秒"
            }
        }
        if schedule.type == .fixedTime {
            guard let cfg = schedule.fixedTime, !cfg.weekdays.isEmpty else {
                return "请至少选择一个重复日"
            }
        }
        return nil
    }
}
