import Foundation
import Darwin

final class UsageStore: @unchecked Sendable {
    static let shared = UsageStore()

    private let defaults: UserDefaults
    private let snapshotKey = "usageSnapshot"
    private let localSnapshotURL: URL
    private let legacySnapshotURL: URL
    private let widgetSnapshotURL: URL

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? .standard
        localSnapshotURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIQuotaMonitor", isDirectory: true)
            .appendingPathComponent("usageSnapshot.json", isDirectory: false)
        legacySnapshotURL = Self.realHomeDirectory
            .appendingPathComponent("Library/Application Support/AIQuotaMonitor", isDirectory: true)
            .appendingPathComponent("usageSnapshot.json", isDirectory: false)
        widgetSnapshotURL = Self.realHomeDirectory
            .appendingPathComponent("Library/Containers/\(AppConstants.widgetBundleIdentifier)/Data/Library/Application Support/AIQuotaMonitor", isDirectory: true)
            .appendingPathComponent("usageSnapshot.json", isDirectory: false)
    }

    func loadSnapshot() -> UsageSnapshot {
        for url in Self.uniqueURLs([localSnapshotURL, widgetSnapshotURL, legacySnapshotURL]) {
            if let data = try? Data(contentsOf: url),
               let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
                return snapshot
            }
        }
        guard let data = defaults.data(forKey: snapshotKey) else { return .empty }
        return (try? JSONDecoder().decode(UsageSnapshot.self, from: data)) ?? .empty
    }

    func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        for url in Self.uniqueURLs([localSnapshotURL, legacySnapshotURL, widgetSnapshotURL]) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
        defaults.set(data, forKey: snapshotKey)
        defaults.synchronize()
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static var realHomeDirectory: URL {
        guard let passwordEntry = getpwuid(getuid()),
              let homePath = passwordEntry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
    }
}
