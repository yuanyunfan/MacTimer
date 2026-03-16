# MacTimer

A native macOS menu bar app for scheduling tasks — no cron syntax required.

MacTimer lives in your menu bar and runs tasks on a schedule: send notifications, run shell scripts, open URLs, or launch apps. Simple enough for non-technical users, powerful enough for developers.

## Features

- **4 task types:** System notification, shell script, open URL, open app
- **2 schedule modes:** Fixed time (e.g., every weekday at 09:00) or interval (e.g., every 2 hours)
- **Menu bar first:** No Dock icon — runs quietly in the background, always available from the menu bar
- **Execution log:** Per-task history with success/failure/timeout status
- **Live stats:** Menu bar popover shows running tasks, paused tasks, and today's upcoming count
- **Instant toggle:** Enable or disable any task without deleting it

## Screenshots

> Coming soon.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (to build from source)

## Build from Source

1. Clone the repo:

   `git clone https://github.com/yuanyunfan/MacTimer.git`

2. Open the project in Xcode:

   `open MacTimer/MacTimer.xcodeproj`

3. In Xcode, go to the `MacTimer` target → `Signing & Capabilities` and select your Apple ID team.

4. Press `Cmd+R` to build and run.

> Note: MacTimer does **not** use the App Sandbox. This is required for shell script execution via `/bin/zsh`. Xcode may show a warning — this is expected.

## Usage

After launching, MacTimer appears in the menu bar (top-right area of your screen).

**Create a task:**
1. Click the menu bar icon → `打开主窗口` (Open Main Window)
2. Click `+ 新建任务` (New Task)
3. Choose a task type and schedule, fill in the details, click Save

**Task types:**

| Type | What it does |
|------|--------------|
| Notification | Sends a macOS system notification with a custom title and body |
| Shell Script | Runs a shell command via `/bin/zsh` (30-second timeout) |
| Open URL | Opens a URL in your default browser |
| Open App | Launches any installed app by bundle ID |

**Schedule modes:**

| Mode | Example |
|------|---------|
| Fixed Time | Every Monday and Friday at 09:00 |
| Interval | Every 30 minutes (minimum: 60 seconds) |

**Execution log:**

Click the log icon on any task row to see its execution history (up to 200 entries, oldest removed automatically).

## Architecture

Three-layer architecture with clear separation of concerns:

```
UI Layer       MenuBarController, MainWindowView, TaskListView, TaskEditorView
               ↕
Service Layer  SchedulerService, TaskExecutor, NotificationService, ScheduleCalculator
               ↕
Data Layer     CoreData (TaskItem, ExecutionLogItem)
```

- `SchedulerService` — `@MainActor` singleton, manages all timers, updates `nextRunAt` after each execution
- `TaskExecutor` — executes tasks, handles concurrency safety for shell processes
- `ScheduleCalculator` — pure logic for computing next fire dates (fixed time + interval)

## Roadmap

- [ ] launchd integration (tasks run even when MacTimer is not running)
- [ ] Task groups and tags
- [ ] iCloud sync
- [ ] Execution history charts

## License

MIT
