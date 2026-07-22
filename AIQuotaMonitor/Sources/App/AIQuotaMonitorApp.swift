import SwiftUI

@main
struct AIQuotaMonitorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 700)

        Settings {
            SettingsView(model: model)
        }
    }
}
