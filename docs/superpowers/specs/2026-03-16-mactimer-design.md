# MacTimer — 设计文档

**日期：** 2026-03-16  
**状态：** 已确认  
**技术栈：** SwiftUI (macOS native)

---

## 1. 产品定位

MacTimer 是一款面向**普通 Mac 用户**的定时任务管理工具。用户可以通过简洁的图形界面配置各种定时任务，无需了解 cron 语法。App 以菜单栏图标形式常驻，提供快速查看和管理入口，同时支持打开完整管理窗口。

---

## 2. 整体架构

分三层，各层职责单一、边界清晰：

```
┌─────────────────────────────────────────┐
│              MacTimer App               │
├──────────────┬──────────────────────────┤
│  UI Layer    │  MenuBarController        │
│  (SwiftUI)   │  MainWindowView           │
│              │  TaskListView (表格)       │
│              │  TaskEditorView (Sheet)   │
├──────────────┼──────────────────────────┤
│  Service     │  SchedulerService         │
│  Layer       │  TaskExecutor             │
│              │  NotificationService      │
├──────────────┼──────────────────────────┤
│  Data Layer  │  CoreData Stack           │
│              │  TaskModel                │
│              │  ScheduleModel            │
└──────────────┴──────────────────────────┘
```

- **UI Layer**：只负责展示和交互，不直接操作数据或执行任务。
- **SchedulerService**：核心调度单例，App 启动时加载并注册所有任务定时器。后续替换为 launchd 只需改此层。
- **TaskExecutor**：实际执行各类任务的执行器，与调度逻辑解耦。
- **CoreData**：持久化任务配置，预留 iCloud 同步扩展能力。

---

## 3. 数据模型

```
Task
├── id: UUID
├── name: String               // 任务名称，如"早晨提醒"
├── isEnabled: Bool            // 启用/暂停开关
├── taskType: Enum
│   ├── shellScript(command: String)
│   ├── openURL(url: String)
│   ├── openApp(bundleID: String)
│   └── notification(title: String, body: String)
├── schedule: Schedule
│   ├── fixedTime(weekdays: [Int], hour: Int, minute: Int)
│   └── interval(seconds: Int, startImmediately: Bool)  // 最小值 60s
├── lastRunAt: Date?
├── nextRunAt: Date?           // 由 SchedulerService 计算并缓存
└── createdAt: Date

ExecutionLog
├── id: UUID
├── taskID: UUID               // 关联 Task
├── executedAt: Date
├── result: Enum (success / failure / timeout)
├── errorMessage: String?      // 失败时记录原因
└── duration: Double?          // 执行耗时（秒），shell 任务适用
```

**设计决策：**
- `isEnabled` 支持暂停而非删除，保留用户历史配置。
- `fixedTime.weekdays` 支持多天（如 [1,3,5] 表示周一三五），避免重复建任务。
- `nextRunAt` 预计算并存储，UI 直接读取，无需每次实时计算。
- Shell 脚本任务保留给有一定技术背景的用户，UI 提供简单命令提示。
- `interval.seconds` 最小值为 60 秒，编辑器层校验，防止资源滥用。
- `ExecutionLog` 最多保留最近 200 条，超出后 FIFO 删除旧记录。

---

## 4. 调度服务

`SchedulerService` 是 App 常驻单例：

```
App 启动
  └─ SchedulerService.start()
       ├─ 从 CoreData 加载所有 isEnabled = true 的任务
       ├─ 计算每个任务的 nextRunAt
       └─ 注册 Timer（精准 fireDate 模式）

Timer 触发
  └─ 检查 nextRunAt <= now 的任务
       └─ TaskExecutor.execute(task)
            ├─ .shellScript  → Process() 执行命令（30s 超时）
            ├─ .openURL      → NSWorkspace.shared.open(url)
            ├─ .openApp      → NSWorkspace.shared.openApplication()
            └─ .notification → UNUserNotificationCenter 发送通知
       └─ 更新 lastRunAt，计算新 nextRunAt，写入 CoreData
```

**错误处理：**
- Shell 执行失败 → 菜单栏图标短暂变红 + 系统通知提示失败原因，写入 ExecutionLog。
- Shell 执行超时（> 30s）→ 强制终止进程，记录超时错误到 ExecutionLog。
- 通知权限未授权 → 创建通知类型任务时弹出系统授权引导。
- openURL 非法格式 → 保存时校验 URL 合法性，不合法则阻止保存。
- openApp App 未安装 → 执行时检测 bundleID 是否有效，无效则写入失败日志 + 通知提醒。

**App 生命周期策略：**
MacTimer 是 `LSUIElement = true` 的 Agent App（无 Dock 图标），菜单栏图标为唯一入口。用户无法通过关闭窗口退出 App，只能通过菜单栏面板的「退出」按钮退出。这保证 App 常驻内存，Timer 始终可以触发。

---

## 5. UI 设计

### 5.1 菜单栏弹出面板

点击状态栏图标弹出，内容：
- 顶部：任务统计（运行中 / 已暂停 / 今日待执行数量）
- 中部：即将执行的任务列表（名称 + 倒计时）
- 底部：「打开主窗口」和「快速新建」入口

### 5.2 主窗口（表格视图）

列：名称 | 类型 | 执行时间 | 下次执行 | 上次执行 | 状态开关 | 操作

- 工具栏：「+ 新建任务」按钮
- 点击行或点击「编辑」→ 弹出 TaskEditorView Sheet

### 5.3 任务编辑器（Sheet）

字段（根据任务类型动态显示）：
- 任务名称（文本输入）
- 任务类型（Pill 选择器：通知 / Shell 脚本 / 打开 App / 打开 URL）
- 执行方式（Pill 选择器：固定时间 / 循环间隔）
- 时间配置（固定时间：重复周期 + 时刻；循环间隔：时间间隔输入，最小 60 秒）
- 任务内容（根据类型动态切换）：
  - 通知：标题 + 正文文本输入
  - Shell 脚本：多行命令输入框，附带简单命令示例提示
  - 打开 App：通过 `NSOpenPanel` 选择 `.app` 文件，存储其 bundleID
  - 打开 URL：单行文本输入，保存时校验 URL 格式合法性

---

## 6. MVP 范围

**第一版包含：**
- [ ] 4 种任务类型（通知、Shell 脚本、打开 App、打开 URL）
- [ ] 2 种调度方式（固定时间、循环间隔）
- [ ] 菜单栏常驻 + 主窗口管理
- [ ] 任务增删改查 + 启用/暂停开关
- [ ] 简单执行日志（最近 50 条）
- [ ] 错误通知提醒

**后续版本（暂不做）：**
- launchd 持久化（App 退出后继续执行）
- 任务分组 / 标签
- iCloud 同步
- 任务执行历史统计图表

---

## 7. 技术决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 语言框架 | Swift + SwiftUI | 原生 Mac 体验，内存占用小，系统集成最深 |
| 数据持久化 | CoreData | 比 JSON 更健壮，支持未来 iCloud 同步 |
| 后台调度（MVP） | Swift Timer + DispatchQueue | 实现简单，足够 MVP 需求 |
| 后台调度（v2） | launchd plist 生成 | App 退出后任务持续运行 |
| 通知 | UNUserNotificationCenter | macOS 标准通知 API |
| Shell 执行 | Foundation Process | macOS 标准进程 API |
