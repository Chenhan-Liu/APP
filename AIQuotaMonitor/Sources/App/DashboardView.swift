import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("视图", selection: $selectedTab) {
                Text("额度概览").tag(0)
                Text("连接账户").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 22)

            if selectedTab == 0 {
                overview
            } else {
                ConnectionView(model: model)
            }
        }
        .background(Color.quotaCanvas)
        .frame(minWidth: 820, minHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 额度看板")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(model.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.refreshNow()
            } label: {
                Label("立即刷新", systemImage: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRefreshing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    private var overview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ForEach(model.snapshot.providers) { provider in
                    UsageCard(provider: provider)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("数据说明", systemImage: "lock.shield")
                    .font(.headline)
                Text("ChatGPT 额度通过本机 Codex 官方服务读取；Claude 优先读取官方使用量接口的结构化响应。登录凭据不会写入 Widget，也不会发送到第三方服务器。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 30)
    }
}

struct UsageCard: View {
    let provider: ProviderSnapshot

    private var window: QuotaWindow { provider.primaryWindow }

    private var tint: Color {
        if provider.id == .chatGPT { return .quotaChatGPT }
        if provider.id == .claude { return .quotaClaude }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(provider.displayName, systemImage: provider.id == .chatGPT ? "bubble.left.and.bubble.right" : "sparkles")
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
                StatusPill(state: window.state)
            }

            CircularUsageRing(provider: provider, window: window, diameter: 154)

            VStack(spacing: 5) {
                Text(window.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("剩余 \(window.remainingPercentText) · \(window.periodText)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                Text(window.resetText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage = window.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 355)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        }
    }
}

struct StatusPill: View {
    let state: UsageState

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch state {
        case .available: return "已同步"
        case .signedOut: return "未登录"
        case .loading: return "同步中"
        case .unavailable: return "待同步"
        }
    }

    private var color: Color {
        switch state {
        case .available: return .green
        case .signedOut: return .orange
        case .loading: return .blue
        case .unavailable: return .secondary
        }
    }
}
