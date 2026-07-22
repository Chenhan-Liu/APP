import SwiftUI

extension Color {
    static let quotaChatGPT = Color(red: 0.18, green: 0.62, blue: 0.43)
    static let quotaClaude = Color(red: 0.83, green: 0.42, blue: 0.23)
    static let quotaInk = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let quotaCanvas = Color(nsColor: .windowBackgroundColor)
}

struct ProviderLogo: View {
    let provider: UsageProvider
    var size: CGFloat = 18

    private var assetName: String {
        provider == .chatGPT ? "ProviderChatGPTLogo" : "ProviderClaudeLogo"
    }

    private var tint: Color {
        provider == .chatGPT ? .quotaChatGPT : .quotaClaude
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }
}

struct CircularUsageRing: View {
    @Environment(\.colorScheme) private var colorScheme

    let provider: ProviderSnapshot
    let window: QuotaWindow
    let diameter: CGFloat

    private var progress: CGFloat {
        CGFloat(window.displayedProgressFraction ?? 0)
    }

    private var tint: Color {
        if provider.id == .chatGPT { return .quotaChatGPT }
        if provider.id == .claude { return .quotaClaude }
        return .accentColor
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: diameter * 0.085)

            if window.displayedProgressFraction != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: diameter * 0.085, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text(window.ringPrimaryText)
                    .font(.system(size: diameter * (window.isCreditBased ? 0.155 : 0.20), weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.quotaInk)
                Text(window.ringSecondaryText)
                    .font(.system(size: diameter * 0.085, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: diameter * 0.72)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName) \(window.title)")
        .accessibilityValue(
            window.isCreditBased
                ? "剩余点数 \(window.ringPrimaryText)"
                : (window.usedFraction == nil ? "暂无精确数据" : "已使用 \(window.usedPercentText)")
        )
    }
}
