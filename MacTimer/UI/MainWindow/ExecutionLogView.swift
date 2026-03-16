import SwiftUI
import CoreData

struct ExecutionLogView: View {
    let taskID: UUID
    let taskName: String

    @FetchRequest private var logs: FetchedResults<ExecutionLogItem>

    init(taskID: UUID, taskName: String) {
        self.taskID = taskID
        self.taskName = taskName
        _logs = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \ExecutionLogItem.executedAt, ascending: false)],
            predicate: NSPredicate(format: "taskID == %@", taskID as CVarArg)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("「\(taskName)」执行日志")
                .font(.headline)
                .padding()

            if logs.isEmpty {
                ContentUnavailableView("暂无执行记录", systemImage: "clock")
            } else {
                List(logs, id: \.id) { log in
                    HStack(spacing: 12) {
                        Image(systemName: log.result.iconName)
                            .foregroundStyle(log.result.color)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.executedAt, style: .relative)
                                .font(.caption)
                            if let msg = log.errorMessage {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if log.duration > 0 {
                            Text(String(format: "%.1fs", log.duration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 280)
    }
}

extension ExecutionResult {
    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .timeout: return "clock.badge.exclamationmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .timeout: return .orange
        }
    }
}
