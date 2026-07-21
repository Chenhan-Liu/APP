import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("刷新") {
                LabeledContent("自动刷新", value: "每 5 分钟")
                LabeledContent("Widget 更新", value: "由 macOS 调度，最早每 5 分钟")
            }

            Section("启动") {
                Toggle("登录 macOS 后自动启动", isOn: Binding(
                    get: { model.autoLaunchEnabled },
                    set: { model.setAutoLaunch($0) }
                ))
            }

            Section("账户与隐私") {
                ForEach(model.snapshot.providers) { provider in
                    Text("\(provider.displayName)：\(provider.primaryWindow.title)")
                }
                Text("主应用读取官方本机服务；Widget 只接收百分比与重置时间。本应用不上传登录信息、Cookie 或额度数据。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 430)
        .padding()
    }
}
