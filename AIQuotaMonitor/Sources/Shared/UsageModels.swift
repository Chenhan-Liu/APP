import Foundation

struct UsageProvider: RawRepresentable, Codable, Hashable, Identifiable, CaseIterable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let chatGPT = UsageProvider(rawValue: "chatGPT")
    static let claude = UsageProvider(rawValue: "claude")
    static let allCases: [UsageProvider] = [.chatGPT, .claude]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .claude: return "Claude"
        default: return rawValue
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum UsageState: String, Codable, Sendable {
    case available
    case unavailable
    case signedOut
    case loading
}

struct QuotaWindow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    var usedFraction: Double?
    var periodLabel: String?
    var resetDescription: String?
    var state: UsageState
    var sourceDescription: String?
    var errorMessage: String?
    var updatedAt: Date?

    var remainingFraction: Double? {
        guard let usedFraction else { return nil }
        return max(0, min(1, 1 - usedFraction))
    }

    var usedPercentText: String {
        guard let usedFraction else { return "—" }
        return "\(Int((usedFraction * 100).rounded()))%"
    }

    var remainingPercentText: String {
        guard let remainingFraction else { return "—" }
        return "\(Int((remainingFraction * 100).rounded()))%"
    }

    var periodText: String { periodLabel ?? "官方使用周期" }
    var resetText: String { resetDescription ?? "重置时间待同步" }

    static func unavailable(
        id: String,
        title: String,
        message: String = "官方页面暂未提供可识别的精确额度"
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            title: title,
            usedFraction: nil,
            periodLabel: nil,
            resetDescription: nil,
            state: .unavailable,
            sourceDescription: "本机官方账户页面",
            errorMessage: message,
            updatedAt: nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case modelName
        case usedFraction
        case periodLabel
        case resetDescription
        case state
        case sourceDescription
        case errorMessage
        case updatedAt
    }

    init(
        id: String,
        title: String,
        usedFraction: Double?,
        periodLabel: String?,
        resetDescription: String?,
        state: UsageState,
        sourceDescription: String?,
        errorMessage: String?,
        updatedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.usedFraction = usedFraction
        self.periodLabel = periodLabel
        self.resetDescription = resetDescription
        self.state = state
        self.sourceDescription = sourceDescription
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .modelName)
            ?? id
        usedFraction = try container.decodeIfPresent(Double.self, forKey: .usedFraction)
        periodLabel = try container.decodeIfPresent(String.self, forKey: .periodLabel)
        resetDescription = try container.decodeIfPresent(String.self, forKey: .resetDescription)
        state = try container.decode(UsageState.self, forKey: .state)
        sourceDescription = try container.decodeIfPresent(String.self, forKey: .sourceDescription)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(usedFraction, forKey: .usedFraction)
        try container.encodeIfPresent(periodLabel, forKey: .periodLabel)
        try container.encodeIfPresent(resetDescription, forKey: .resetDescription)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(sourceDescription, forKey: .sourceDescription)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct ProviderSnapshot: Codable, Identifiable, Equatable, Sendable {
    let id: UsageProvider
    var displayName: String
    var windows: [QuotaWindow]

    var primaryWindow: QuotaWindow {
        windows.first ?? .unavailable(id: "\(id.rawValue)-primary", title: displayName)
    }

    static func unavailable(
        id: UsageProvider,
        windowTitle: String,
        message: String = "官方页面暂未提供可识别的精确额度"
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            displayName: id.displayName,
            windows: [.unavailable(id: "\(id.rawValue)-primary", title: windowTitle, message: message)]
        )
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var providers: [ProviderSnapshot]
    var lastRefreshAt: Date?

    init(providers: [ProviderSnapshot], lastRefreshAt: Date?) {
        schemaVersion = Self.currentSchemaVersion
        self.providers = providers
        self.lastRefreshAt = lastRefreshAt
    }

    func provider(_ id: UsageProvider) -> ProviderSnapshot? {
        providers.first { $0.id == id }
    }

    static let empty = UsageSnapshot(
        providers: [
            .unavailable(id: .chatGPT, windowTitle: AppConstants.chatGPTDefaultWindowTitle),
            .unavailable(id: .claude, windowTitle: AppConstants.claudeDefaultWindowTitle)
        ],
        lastRefreshAt: nil
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case providers
        case lastRefreshAt
        case chatGPT
        case claude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshAt)

        if let decodedProviders = try container.decodeIfPresent([ProviderSnapshot].self, forKey: .providers) {
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.currentSchemaVersion
            providers = decodedProviders
            return
        }

        schemaVersion = Self.currentSchemaVersion
        var migratedProviders: [ProviderSnapshot] = []
        if let chatGPTWindow = try container.decodeIfPresent(QuotaWindow.self, forKey: .chatGPT) {
            migratedProviders.append(ProviderSnapshot(
                id: .chatGPT,
                displayName: UsageProvider.chatGPT.displayName,
                windows: [chatGPTWindow]
            ))
        }
        if let claudeWindow = try container.decodeIfPresent(QuotaWindow.self, forKey: .claude) {
            migratedProviders.append(ProviderSnapshot(
                id: .claude,
                displayName: UsageProvider.claude.displayName,
                windows: [claudeWindow]
            ))
        }
        providers = migratedProviders.isEmpty ? Self.empty.providers : migratedProviders
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(providers, forKey: .providers)
        try container.encodeIfPresent(lastRefreshAt, forKey: .lastRefreshAt)
    }
}

enum AppConstants {
    static let appGroupIdentifier = "group.com.thanaloid.AIQuotaMonitor"
    static let widgetBundleIdentifier = "com.thanaloid.AIQuotaMonitor.Widget"
    static let refreshInterval: TimeInterval = 5 * 60
    static let chatGPTDefaultWindowTitle = "GPT-5.6 Sol"
    static let claudeDefaultWindowTitle = "Claude Fable 5"
    static let chatGPTLoginURL = URL(string: "https://chatgpt.com/")!
    static let claudeLoginURL = URL(string: "https://claude.ai/")!
    static let chatGPTUsageURL = URL(string: "https://chatgpt.com/settings/usage")!
    static let claudeUsageURL = URL(string: "https://claude.ai/settings/usage")!
}
