import SwiftUI

struct ConnectionView: View {
    @ObservedObject var model: AppModel
    @State private var provider: UsageProvider = .chatGPT

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider == .chatGPT ? "ChatGPT 本机连接" : "Claude 官方会话")
                        .font(.title3.weight(.semibold))
                    Text(provider == .chatGPT
                         ? "自动使用 ChatGPT/Codex 已登录账户，无需在这里再次登录。"
                         : "Claude 登录状态只保存在本机 WebKit 会话中，用于读取官方结构化使用量响应。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("平台", selection: $provider) {
                    Text("ChatGPT").tag(UsageProvider.chatGPT)
                    Text("Claude").tag(UsageProvider.claude)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            if provider == .chatGPT {
                ContentUnavailableView(
                    "使用本机结构化接口",
                    systemImage: "checkmark.shield",
                    description: Text("点击“读取使用量”即可从 ChatGPT 自带的 Codex 服务取得周额度和重置时间。")
                )
                .frame(minHeight: 330)
            } else {
                WebSessionView(webView: model.webSessions.webView(for: provider))
                    .frame(minHeight: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }
            }

            HStack {
                if provider == .claude {
                    Button("打开登录页") {
                        model.webSessions.loadLoginPage(for: provider)
                    }
                    Button("打开使用量页") {
                        model.webSessions.openUsagePage(for: provider)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("读取使用量") {
                    model.refreshNow()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 30)
        .onAppear {
            if provider == .claude && model.webSessions.webView(for: provider).url == nil {
                model.webSessions.loadLoginPage(for: provider)
            }
        }
        .onChange(of: provider) { _, newValue in
            if newValue == .claude && model.webSessions.webView(for: newValue).url == nil {
                model.webSessions.loadLoginPage(for: newValue)
            }
        }
    }
}
