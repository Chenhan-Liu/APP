import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct QuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        QuotaWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaWidgetEntry) -> Void) {
        completion(QuotaWidgetEntry(date: Date(), snapshot: UsageStore.shared.loadWidgetSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaWidgetEntry>) -> Void) {
        let now = Date()
        let entry = QuotaWidgetEntry(date: now, snapshot: UsageStore.shared.loadWidgetSnapshot())
        let refreshDate = now.addingTimeInterval(AppConstants.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct AIQuotaWidget: Widget {
    let kind = AppConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaWidgetProvider()) { entry in
            QuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("AI 额度")
        .description("显示已连接 AI 服务的本地官方额度状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallLayout
        case .systemLarge:
            largeLayout
        default:
            mediumLayout
        }
    }

    private var smallLayout: some View {
        let provider = entry.snapshot.provider(.chatGPT)
            ?? entry.snapshot.providers.first
            ?? UsageSnapshot.empty.providers[0]
        let window = provider.primaryWindow

        return VStack(spacing: 8) {
            Text("AI 额度")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            CircularUsageRing(provider: provider, window: window, diameter: 92)
            Text(window.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(provider.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color.quotaCanvas }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI 额度")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let updatedAt = entry.snapshot.lastRefreshAt {
                    Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 9) {
                ForEach(Array(entry.snapshot.providers.prefix(2).enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { Divider() }
                    WidgetMetricView(provider: provider, style: .compact)
                }
            }
        }
        .padding(.horizontal, 2)
        .containerBackground(for: .widget) { Color.quotaCanvas }
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI 额度")
                    .font(.headline.weight(.bold))
                Spacer()
                if let updatedAt = entry.snapshot.lastRefreshAt {
                    Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(entry.snapshot.providers.prefix(2).enumerated()), id: \.element.id) { index, provider in
                if index > 0 { Divider() }
                WidgetMetricView(provider: provider, style: .expanded)
            }
        }
        .containerBackground(for: .widget) { Color.quotaCanvas }
    }
}

struct WidgetMetricView: View {
    let provider: ProviderSnapshot
    let style: WidgetMetricStyle

    private var window: QuotaWindow { provider.primaryWindow }

    var body: some View {
        switch style {
        case .compact:
            compactBody
        case .expanded:
            expandedBody
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ProviderLogo(provider: provider.id, size: 13)
                Text(provider.displayName)
            }
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            HStack(spacing: 6) {
                CircularUsageRing(provider: provider, window: window, diameter: 60)

                VStack(alignment: .leading, spacing: 2) {
                    Text(compactTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .allowsTightening(true)
                    Text(window.compactCreditText)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                        .allowsTightening(true)
                    Text(compactPeriod)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .allowsTightening(true)
                    if !compactReset.isEmpty {
                        Text(compactReset)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .allowsTightening(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedBody: some View {
        HStack(spacing: 12) {
            CircularUsageRing(provider: provider, window: window, diameter: 86)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    ProviderLogo(provider: provider.id, size: 18)
                    Text(provider.displayName)
                }
                .font(.headline.weight(.bold))
                Text(window.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(window.summaryText)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !window.detailText.isEmpty {
                    Text(window.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactTitle: String {
        switch window.title {
        case "GPT-5.6 Sol": return "GPT-5.6"
        case "Claude Fable 5": return "Fable 5"
        default: return window.title
        }
    }

    private var compactPeriod: String {
        if window.isCreditBased {
            guard let balance = window.creditBalance,
                  let total = window.creditTotal,
                  total > 0 else { return "点数余额" }
            return "已用 \(window.formattedMoney(max(0, total - balance)))"
        }
        let period = window.periodText
        if period == "Fable 每周额度" { return "Fable 每周" }
        if period.hasSuffix("额度") { return String(period.dropLast(2)) }
        return period
    }

    private var compactReset: String {
        if window.isCreditBased { return "" }
        if window.resetText == "重置时间待同步" { return "重置待同步" }
        return window.detailText
    }
}

enum WidgetMetricStyle {
    case compact
    case expanded
}

@main
struct AIQuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIQuotaWidget()
    }
}
