import Foundation

struct UsagePageParser {
    static func parse(provider: UsageProvider, pageText: String, now: Date = Date()) -> QuotaWindow {
        let windowTitle = provider == .chatGPT
            ? AppConstants.chatGPTDefaultWindowTitle
            : AppConstants.claudeDefaultWindowTitle
        let normalized = pageText.replacingOccurrences(of: "\u{00a0}", with: " ")

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unavailable(id: "\(provider.rawValue)-primary", title: windowTitle, message: "官方页面没有返回内容")
        }

        if provider == .claude, let credits = parseClaudeCredits(in: normalized, now: now) {
            return credits
        }

        let searchTerms: [String]
        if provider == .chatGPT {
            searchTerms = ["GPT-5.6 Sol", "GPT-5.6", "Sol", "GPT-5"]
        } else if provider == .claude {
            searchTerms = ["Claude Fable 5", "Fable 5", "Fable"]
        } else {
            searchTerms = [windowTitle, provider.displayName]
        }

        let scopedText = scopedText(in: normalized, around: searchTerms) ?? normalized
        let usedFraction = findUsedFraction(in: scopedText)
        let period = findPeriod(in: scopedText, provider: provider)
        let reset = findResetDescription(in: scopedText)

        guard let usedFraction else {
            let message = looksSignedOut(normalized)
                ? "请先在官方页面登录"
                : "官方页面暂未提供可识别的精确额度"
            var unavailable = QuotaWindow.unavailable(
                id: "\(provider.rawValue)-primary",
                title: windowTitle,
                message: message
            )
            unavailable.state = looksSignedOut(normalized) ? .signedOut : .unavailable
            unavailable.updatedAt = now
            return unavailable
        }

        return QuotaWindow(
            id: "\(provider.rawValue)-primary",
            title: windowTitle,
            usedFraction: usedFraction,
            periodLabel: period,
            resetDescription: reset,
            state: .available,
            sourceDescription: "本机官方账户页面",
            errorMessage: nil,
            updatedAt: now
        )
    }

    private static func scopedText(in text: String, around terms: [String]) -> String? {
        let lowercased = text.lowercased()
        guard let match = terms.compactMap({ lowercased.range(of: $0.lowercased()) }).first else { return nil }
        let start = lowercased.index(match.lowerBound, offsetBy: -min(500, lowercased.distance(from: lowercased.startIndex, to: match.lowerBound)))
        let end = lowercased.index(match.upperBound, offsetBy: min(900, lowercased.distance(from: match.upperBound, to: lowercased.endIndex)))
        return String(text[start..<end])
    }

    private static func parseClaudeCredits(in text: String, now: Date) -> QuotaWindow? {
        let balanceLabels = "current balance|available balance|remaining balance|現在の残高|当前余额|目前余额|可用余额|剩余余额"
        let promotionalLabels = "promotional credits?|promotion credits?|promo credits?|プロモーションクレジット|促销点数|促销额度|推广点数"

        let balance = firstMoney(in: text, patterns: [
            "(?is)\\$\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\s*(?:\(balanceLabels))",
            "(?is)(?:\(balanceLabels))[^$]{0,80}\\$\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
        ])
        guard let balance else { return nil }

        let promotionalTotal = firstMoney(in: text, patterns: [
            "(?is)\\$\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)\\s*(?:\(promotionalLabels))",
            "(?is)(?:\(promotionalLabels))[^$]{0,80}\\$\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
        ])
        let hasPromotionalCredit = text.range(
            of: promotionalLabels,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let total = promotionalTotal
            ?? (hasPromotionalCredit ? AppConstants.claudeFablePromotionalCreditTotal : nil)
        let expiration = firstMatch(
            in: text,
            pattern: #"(?is)(?:expires?|expiration|expiry|有効期限|有效期|到期)\s*[：:]?\s*([^\n]{1,40})"#
        )?.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)

        return QuotaWindow(
            id: "claude-primary",
            title: AppConstants.claudeDefaultWindowTitle,
            usedFraction: nil,
            periodLabel: "点数余额",
            resetDescription: nil,
            state: .available,
            sourceDescription: "Claude 官方点数数据",
            errorMessage: nil,
            updatedAt: now,
            creditBalance: balance,
            creditTotal: total,
            currencyCode: "USD",
            creditExpirationDescription: expiration.map { "有效期至 \($0)" } ?? "点数有效期待同步"
        )
    }

    private static func firstMoney(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let match = firstMatch(in: text, pattern: pattern), match.count > 1 else { continue }
            let normalized = match[1].replacingOccurrences(of: ",", with: "")
            if let value = Double(normalized) { return value }
        }
        return nil
    }

    private static func findUsedFraction(in text: String) -> Double? {
        // Prefer explicit remaining values. Usage pages often contain unrelated
        // zero-valued loading progress bars elsewhere in the DOM.
        let remainingPatterns = [
            #"(?i)(?:remaining|left|available|残り|剩余)\D{0,16}(\d{1,3})\s*%"#,
            #"(?i)(\d{1,3})\s*%\s*(?:remaining|left|available|残り|剩余)"#
        ]

        for pattern in remainingPatterns {
            if let value = firstNumber(in: text, matching: pattern) {
                return 1 - value / 100
            }
        }

        let focusedText = quotaFocusedText(from: text)
        let usedPatterns = [
            #"(?i)(\d{1,3})\s*%\s*(?:used|已使用|使用済み|utilized|consumed)"#,
            #"(?i)(?:used|已使用|使用済み|utilized|consumed)\D{0,24}(\d{1,3})\s*%"#,
            #"(?i)(?:usage|plan usage|quota usage|使用量|利用量|额度使用)\D{0,32}(\d{1,3})\s*%"#,
            #"(?i)(\d{1,3})\s*%\D{0,20}(?:of (?:the )?(?:limit|quota)|上限|额度)"#
        ]

        for pattern in usedPatterns {
            if let value = firstNumber(in: focusedText, matching: pattern) {
                return value / 100
            }
        }

        if let match = firstMatch(in: focusedText, pattern: #"(?i)\b(\d{1,3})\s*(?:of|/|\s)\s*(\d{1,3})\s*(?:messages?|条|requests?)\b"#),
           match.count > 2, let used = Double(match[1]), let total = Double(match[2]), total > 0, used <= total {
            return used / total
        }

        return nil
    }

    private static func findPeriod(in text: String, provider: UsageProvider) -> String? {
        let lowercased = text.lowercased()
        if lowercased.contains("5-hour") || lowercased.contains("5 hour") || text.contains("5小时") || text.contains("5 時間") {
            return "5 小时额度"
        }
        if lowercased.contains("weekly") || text.contains("每周") || lowercased.contains("week") || text.contains("週間") || text.contains("週次") {
            return "每周额度"
        }
        if lowercased.contains("daily") || text.contains("每日") || lowercased.contains("day") || text.contains("日次") {
            return "每日额度"
        }
        return provider == .claude ? "官方使用额度" : "官方消息额度"
    }

    private static func findResetDescription(in text: String) -> String? {
        let patterns = [
            #"(?i)(\d{4}[/-]\d{1,2}[/-]\d{1,2}\s+\d{1,2}:\d{2}\s*(?:に)?(?:リセット|reset))"#,
            #"(?i)(\d{1,2}[/-]\d{1,2}\s+\d{1,2}:\d{2}\s*(?:に)?(?:リセット|reset))"#,
            #"(?i)(?:resets?|resetting|恢复|重置)\D{0,12}([^\n.]{1,40})"#,
            #"(?i)(?:リセット)\D{0,12}([^\n.]{1,40})"#,
            #"(?i)(?:in|在)\s*([0-9]{1,2}\s*(?:h|hr|hour|小时|m|min|分钟)[^\n.]*)"#
        ]
        for pattern in patterns {
            if let match = firstMatch(in: text, pattern: pattern), let value = match.last?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func looksSignedOut(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("log in") || lowercased.contains("sign in") || text.contains("登录") || text.contains("ログイン")
    }

    private static func quotaFocusedText(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let keywords = [
            "usage", "limit", "quota", "weekly", "daily", "remaining",
            "使用量", "利用量", "上限", "週間", "週次", "日次", "残り", "剩余", "额度"
        ]

        var selected = IndexSet()
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            guard keywords.contains(where: { lowercased.contains($0.lowercased()) }) else { continue }
            let start = max(0, index - 2)
            let end = min(lines.count - 1, index + 2)
            selected.insert(integersIn: start...end)
        }

        if selected.isEmpty { return text }
        return selected.map { lines[$0] }.joined(separator: "\n")
    }

    private static func firstNumber(in text: String, matching pattern: String) -> Double? {
        guard let match = firstMatch(in: text, pattern: pattern), match.count > 1 else { return nil }
        return Double(match[1])
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
