import SwiftUI
import AppKit

struct PayloadEditorSection: View {
    @Binding var taskType: TaskType
    @Binding var payload: TaskPayload

    var body: some View {
        Section("任务内容") {
            switch taskType {
            case .notification:
                TextField("标题", text: Binding(
                    get: { payload.notificationTitle ?? "" },
                    set: { payload.notificationTitle = $0 }
                ))
                TextField("正文", text: Binding(
                    get: { payload.notificationBody ?? "" },
                    set: { payload.notificationBody = $0 }
                ))

            case .shellScript:
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: Binding(
                        get: { payload.command ?? "" },
                        set: { payload.command = $0 }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                    Text("示例：open -a Safari / say \"Hello\" / /usr/local/bin/my-script.sh")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .openURL:
                TextField("URL（例如 https://example.com）", text: Binding(
                    get: { payload.urlString ?? "" },
                    set: { payload.urlString = $0 }
                ))

            case .openApp:
                HStack {
                    if let name = payload.appDisplayName {
                        Label(name, systemImage: "app")
                            .lineLimit(1)
                    } else {
                        Text("未选择 App").foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("选择 App…") { pickApp() }
                }
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "选择要打开的 App"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        guard let bundleID = bundle?.bundleIdentifier else {
            // App has no bundle identifier — can't be used as an openApp target.
            return
        }
        payload.bundleID = bundleID
        payload.appDisplayName = url.deletingPathExtension().lastPathComponent
    }
}
