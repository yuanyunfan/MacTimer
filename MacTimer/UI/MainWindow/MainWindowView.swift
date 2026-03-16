import SwiftUI

enum EditorMode: Identifiable {
    case create
    case edit(TaskItem)
    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let t): return t.objectID.uriRepresentation().absoluteString
        }
    }
}

struct MainWindowView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var scheduler: SchedulerService
    @State private var editorMode: EditorMode? = nil

    var body: some View {
        TaskListView(
            onEdit: { task in
                editorMode = .edit(task)
            }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorMode = .create
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            TaskEditorView(
                task: { if case .edit(let t) = mode { return t } else { return nil } }(),
                onDismiss: { editorMode = nil }
            )
            .environment(\.managedObjectContext, context)
            .environmentObject(scheduler)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}

