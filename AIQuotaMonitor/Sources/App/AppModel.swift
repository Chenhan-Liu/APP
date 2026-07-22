import Combine
import Foundation
import ServiceManagement
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: UsageSnapshot
    @Published var isRefreshing = false
    @Published var statusMessage = "额度从本机官方结构化数据读取"
    @Published var autoLaunchEnabled: Bool

    let webSessions = WebUsageCoordinator()
    private var refreshTimer: Timer?

    init() {
        snapshot = UsageStore.shared.loadSnapshot()
        autoLaunchEnabled = LaunchAtLogin.isEnabled
        startRefreshTimer()
        Task { @MainActor [weak self] in
            self?.refreshNow()
        }
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = "正在读取 ChatGPT 与 Claude 官方额度…"

        Task { [weak self] in
            guard let self else { return }
            let nextSnapshot = await webSessions.refreshAll()
            let stabilizedSnapshot = nextSnapshot.preservingRecentClaudeCredits(from: snapshot)
            snapshot = stabilizedSnapshot
            UsageStore.shared.save(stabilizedSnapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.widgetKind)
            WidgetCenter.shared.reloadAllTimelines()
            isRefreshing = false
            statusMessage = "已更新：\(stabilizedSnapshot.lastRefreshAt?.formatted(date: .omitted, time: .shortened) ?? "刚刚")"
        }
    }

    func setAutoLaunch(_ enabled: Bool) {
        do {
            if enabled {
                try LaunchAtLogin.enable()
            } else {
                try LaunchAtLogin.disable()
            }
            autoLaunchEnabled = enabled
        } catch {
            autoLaunchEnabled = LaunchAtLogin.isEnabled
            statusMessage = "无法修改开机启动：\(error.localizedDescription)"
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
