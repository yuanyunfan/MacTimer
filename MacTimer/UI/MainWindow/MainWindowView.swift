import SwiftUI

struct MainWindowView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var scheduler: SchedulerService
    @State private var showingEditor = false
    @State private var editingTask: TaskItem?

    var body: some View {
        TaskListView(
            onEdit: { task in
                editingTask = task
                showingEditor = true
            }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingTask = nil
                    showingEditor = true
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
            }
        }
        // TODO(Task 10): Replace with .sheet(item: $editingTask) to avoid race condition
        // when user rapidly switches between edit and new-task modes.
        .sheet(isPresented: $showingEditor) {
            TaskEditorView(task: editingTask) {
                showingEditor = false
            }
            .environment(\.managedObjectContext, context)
            .environmentObject(scheduler)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}

// Stub — will be replaced in Task 10
struct TaskEditorView: View {
    let task: TaskItem?
    let onDismiss: () -> Void
    var body: some View { Text("Editor — Coming Soon") }
}
