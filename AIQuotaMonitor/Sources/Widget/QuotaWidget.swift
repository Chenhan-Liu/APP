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
        completion(QuotaWidgetEntry(date: Date(), snapshot: UsageStore.shared.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaWidgetEntry>) -> Void) {
        let now = Date()
        let entry = QuotaWidgetEntry(date: now, snapshot: UsageStore.shared.loadSnapshot())
        let refreshDate = now.addingTimeInterval(AppConstants.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct AIQuotaWidget: Widget {
    let kind = "AIQuotaWidget"

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI 额度")
                    .font(.headline.weight(.bold))
                Spacer()
                if let updatedAt = entry.snapshot.lastRefreshAt {
                    Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 18) {
                ForEach(Array(entry.snapshot.providers.prefix(2).enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { Divider() }
                    WidgetMetricView(provider: provider)
                }
            }
        }
        .containerBackground(for: .widget) { Color.quotaCanvas }
    }
}

struct WidgetMetricView: View {
    let provider: ProviderSnapshot

    private var window: QuotaWindow { provider.primaryWindow }

    var body: some View {
        HStack(spacing: 10) {
            CircularUsageRing(provider: provider, window: window, diameter: 82)

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.displayName)
                    .font(.subheadline.weight(.bold))
                Text(window.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("剩余 \(window.remainingPercentText)")
                    .font(.caption)
                Text(window.periodText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(window.resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct AIQuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIQuotaWidget()
    }
}
