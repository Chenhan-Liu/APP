import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class WebUsageCoordinator: NSObject, ObservableObject, WKNavigationDelegate {
    let chatGPTWebView: WKWebView
    let claudeWebView: WKWebView

    @Published private(set) var lastNavigationMessage = "等待连接账户"

    override init() {
        chatGPTWebView = Self.makeWebView(captureUsageResponses: false)
        claudeWebView = Self.makeWebView(captureUsageResponses: true)
        super.init()

        chatGPTWebView.navigationDelegate = self
        claudeWebView.navigationDelegate = self
        claudeWebView.allowsBackForwardNavigationGestures = true
    }

    private static func makeWebView(captureUsageResponses: Bool) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        if captureUsageResponses {
            configuration.userContentController.addUserScript(WKUserScript(
                source: Self.responseCaptureScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        return WKWebView(frame: .zero, configuration: configuration)
    }

    func webView(for provider: UsageProvider) -> WKWebView {
        provider == .chatGPT ? chatGPTWebView : claudeWebView
    }

    func loadLoginPage(for provider: UsageProvider) {
        let url = provider == .chatGPT ? AppConstants.chatGPTLoginURL : AppConstants.claudeLoginURL
        webView(for: provider).load(URLRequest(url: url))
        lastNavigationMessage = "正在打开 \(provider.displayName) 官方页面"
    }

    func openUsagePage(for provider: UsageProvider) {
        let url = provider == .chatGPT ? AppConstants.chatGPTUsageURL : AppConstants.claudeUsageURL
        webView(for: provider).load(URLRequest(url: url))
        lastNavigationMessage = "正在打开 \(provider.displayName) 使用量页面"
    }

    func refreshAll() async -> UsageSnapshot {
        let chatGPTWindow = await Task.detached(priority: .userInitiated) {
            CodexUsageCollector.collect()
        }.value
        let claudeWindow = await refreshClaude()
        return UsageSnapshot(
            providers: [
                ProviderSnapshot(id: .chatGPT, displayName: UsageProvider.chatGPT.displayName, windows: [chatGPTWindow]),
                ProviderSnapshot(id: .claude, displayName: UsageProvider.claude.displayName, windows: [claudeWindow])
            ],
            lastRefreshAt: Date()
        )
    }

    private func refreshClaude() async -> QuotaWindow {
        let view = claudeWebView
        let usageURL = AppConstants.claudeUsageURL

        if view.url?.host != usageURL.host || view.url?.path != usageURL.path {
            view.load(URLRequest(url: usageURL))
        } else {
            view.reload()
        }

        let deadline = Date().addingTimeInterval(20)
        var latestPageText = ""
        var latestStructuredMetric: QuotaWindow?

        while Date() < deadline {
            do {
                let captured = try await capturedResponses(from: view)
                if let metric = ClaudeStructuredUsageParser.parse(capturedJSON: captured) {
                    if metric.isCreditBased { return metric }
                    latestStructuredMetric = metric
                }

                latestPageText = try await pageText(from: view)
                let pageMetric = UsagePageParser.parse(provider: .claude, pageText: latestPageText)
                if pageMetric.isCreditBased { return pageMetric }
                if !view.isLoading, pageMetric.state == .signedOut {
                    return pageMetric
                }
            } catch {
                // The page may still be navigating; retry until the deadline.
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        var fallback = UsagePageParser.parse(provider: .claude, pageText: latestPageText)
        if fallback.isCreditBased { return fallback }
        if let latestStructuredMetric { return latestStructuredMetric }
        if fallback.state != .available {
            fallback.errorMessage = "未捕获到 Claude 官方结构化使用量，请确认已登录并打开使用量页"
        }
        return fallback
    }

    private func capturedResponses(from webView: WKWebView) async throws -> String {
        let script = "JSON.stringify(window.__aiQuotaResponses || [])"
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String ?? "[]")
                }
            }
        }
    }

    private func pageText(from webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.body?.innerText || ''") { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String ?? "")
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.lastNavigationMessage = "官方页面已加载"
        }
    }

    private static let responseCaptureScript = #"""
    (() => {
      if (window.__aiQuotaCaptureInstalled) return;
      window.__aiQuotaCaptureInstalled = true;
      window.__aiQuotaResponses = [];

      const shouldKeep = (url, text) => {
        const sample = `${url} ${text.slice(0, 12000)}`;
        return /usage|limit|quota|five_hour|seven_day|weekly_scoped|utilization|fable|credit|balance|promotion|billing|spend/i.test(sample);
      };

      const save = (url, text) => {
        try {
          if (!text || !shouldKeep(url, text)) return;
          window.__aiQuotaResponses.push({ url: String(url || ''), body: text.slice(0, 250000) });
          if (window.__aiQuotaResponses.length > 40) window.__aiQuotaResponses.shift();
        } catch (_) {}
      };

      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        const response = await originalFetch.apply(this, args);
        try {
          const url = response.url || args[0]?.url || args[0] || '';
          response.clone().text().then(text => save(url, text)).catch(() => {});
        } catch (_) {}
        return response;
      };

      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__aiQuotaURL = url;
        return originalOpen.call(this, method, url, ...rest);
      };
      XMLHttpRequest.prototype.send = function(...args) {
        this.addEventListener('load', () => {
          try {
            if (typeof this.responseText === 'string') save(this.responseURL || this.__aiQuotaURL, this.responseText);
          } catch (_) {}
        });
        return originalSend.apply(this, args);
      };
    })();
    """#
}

private enum LocalCollectorError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

private enum CodexUsageCollector {
    static func collect() -> QuotaWindow {
        let now = Date()
        do {
            let executable = try codexExecutable()
            let client = try CodexRPCClient(executableURL: executable)
            defer { client.stop() }

            _ = try client.call(
                method: "initialize",
                params: ["clientInfo": [
                    "name": "ai-quota-monitor",
                    "title": "AI Quota Monitor",
                    "version": "1.0"
                ]]
            )
            try client.notify(method: "initialized", params: [:])
            let result = try client.call(method: "account/rateLimits/read", params: [:])
            let rateLimits = preferredRateLimits(from: result)
            let window = preferredWindow(from: rateLimits)

            guard let usedPercent = number(window["usedPercent"] ?? window["used_percent"]) else {
                throw LocalCollectorError.unavailable("Codex 没有返回可识别的额度百分比")
            }

            let duration = number(window["windowDurationMins"] ?? window["window_duration_mins"])
            let reset = resetDate(window["resetsAt"] ?? window["resets_at"])

            return QuotaWindow(
                id: "chatGPT-primary",
                title: AppConstants.chatGPTDefaultWindowTitle,
                usedFraction: max(0, min(1, usedPercent / 100)),
                periodLabel: periodLabel(minutes: duration),
                resetDescription: reset.map(resetDescription),
                state: .available,
                sourceDescription: "ChatGPT Codex 本机服务",
                errorMessage: nil,
                updatedAt: now
            )
        } catch {
            var metric = QuotaWindow.unavailable(
                id: "chatGPT-primary",
                title: AppConstants.chatGPTDefaultWindowTitle,
                message: error.localizedDescription
            )
            metric.sourceDescription = "ChatGPT Codex 本机服务"
            metric.state = error.localizedDescription.localizedCaseInsensitiveContains("account") ? .signedOut : .unavailable
            metric.updatedAt = now
            return metric
        }
    }

    private static func codexExecutable() throws -> URL {
        let paths = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let path = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw LocalCollectorError.unavailable("未找到 ChatGPT/Codex 本机程序")
        }
        return URL(fileURLWithPath: path)
    }

    private static func preferredRateLimits(from result: [String: Any]) -> [String: Any] {
        if let direct = result["rateLimits"] as? [String: Any], hasWindow(direct) {
            return direct
        }
        if let byID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byID["codex"] as? [String: Any] {
            return codex
        }
        return result
    }

    private static func hasWindow(_ value: [String: Any]) -> Bool {
        value["primary"] is [String: Any] || value["secondary"] is [String: Any]
    }

    private static func preferredWindow(from rateLimits: [String: Any]) -> [String: Any] {
        let windows = ["primary", "secondary"].compactMap { rateLimits[$0] as? [String: Any] }
        return windows.max {
            number($0["windowDurationMins"] ?? $0["window_duration_mins"]) ?? 0
                < number($1["windowDurationMins"] ?? $1["window_duration_mins"]) ?? 0
        } ?? [:]
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func resetDate(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            return Date(timeIntervalSince1970: seconds > 20_000_000_000 ? seconds / 1000 : seconds)
        }
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func periodLabel(minutes: Double?) -> String {
        guard let minutes else { return "官方使用额度" }
        if minutes >= 7 * 24 * 60 { return "每周额度" }
        if minutes >= 24 * 60 { return "每日额度" }
        let hours = max(1, Int((minutes / 60).rounded()))
        return "\(hours) 小时额度"
    }

    private static func resetDescription(_ date: Date) -> String {
        "\(date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN")))) 重置"
    }
}

private final class CodexRPCClient: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var nextID = 1
    private var responses: [Int: Result<[String: Any], Error>] = [:]
    private var semaphores: [Int: DispatchSemaphore] = [:]

    init(executableURL: URL) throws {
        process.executableURL = executableURL
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] process in
            self?.failPending("Codex 本机服务已退出（\(process.terminationStatus)）")
        }
        try process.run()
    }

    func call(method: String, params: [String: Any], timeout: TimeInterval = 20) throws -> [String: Any] {
        let id: Int
        let semaphore = DispatchSemaphore(value: 0)

        lock.lock()
        id = nextID
        nextID += 1
        semaphores[id] = semaphore
        lock.unlock()

        do {
            try write(["method": method, "id": id, "params": params])
        } catch {
            lock.lock()
            semaphores.removeValue(forKey: id)
            lock.unlock()
            throw error
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            lock.lock()
            semaphores.removeValue(forKey: id)
            responses.removeValue(forKey: id)
            lock.unlock()
            throw LocalCollectorError.unavailable("\(method) 读取超时")
        }

        lock.lock()
        let result = responses.removeValue(forKey: id)
        semaphores.removeValue(forKey: id)
        lock.unlock()

        return try result?.get() ?? { throw LocalCollectorError.unavailable("Codex 返回为空") }()
    }

    func notify(method: String, params: [String: Any]) throws {
        try write(["method": method, "params": params])
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue,
                  let semaphore = semaphores[id] else { continue }

            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Codex 接口错误"
                responses[id] = .failure(LocalCollectorError.unavailable(message))
            } else {
                responses[id] = .success(object["result"] as? [String: Any] ?? [:])
            }
            semaphore.signal()
        }
        lock.unlock()
    }

    private func failPending(_ message: String) {
        lock.lock()
        for (id, semaphore) in semaphores {
            responses[id] = .failure(LocalCollectorError.unavailable(message))
            semaphore.signal()
        }
        lock.unlock()
    }
}

private enum ClaudeStructuredUsageParser {
    static func parse(capturedJSON: String, now: Date = Date()) -> QuotaWindow? {
        guard let data = capturedJSON.data(using: .utf8),
              let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let payloads: [Any] = records.reversed().compactMap { record in
            guard let body = record["body"] as? String,
                  let bodyData = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: bodyData) else { return nil }
            return json
        }

        // Claude loads plan limits and Usage Credits through separate requests.
        // Scan every captured response for credits before considering the older
        // percentage-based limits so Fable's billing source always wins.
        for json in payloads {
            if let metric = creditMetric(in: json, now: now) { return metric }
        }
        for json in payloads {
            let dictionaries = allDictionaries(in: json)
            if let metric = fableMetric(in: dictionaries, now: now) { return metric }
        }
        for json in payloads {
            let dictionaries = allDictionaries(in: json)
            if let metric = standardMetric(in: dictionaries, now: now) { return metric }
        }
        return nil
    }

    private struct ScalarValue {
        let path: String
        let value: Any
    }

    private static func creditMetric(in json: Any, now: Date) -> QuotaWindow? {
        let values = scalarValues(in: json)
        let balanceCandidates = values.compactMap { candidate -> (score: Int, amount: Double)? in
            let path = candidate.path.lowercased()
            guard path.contains("balance") || path.contains("available_amount") || path.contains("remaining_amount") else {
                return nil
            }
            guard !path.contains("limit"), !path.contains("spent"), !path.contains("used") else { return nil }
            guard let amount = moneyNumber(candidate.value, path: path) else { return nil }
            var score = 10
            if path.contains("current") { score += 8 }
            if path.contains("credit") { score += 5 }
            if path.contains("available") || path.contains("remaining") { score += 4 }
            if path.contains("promo") || path.contains("grant") { score -= 5 }
            return (score, amount)
        }
        let promotionalCandidates = values.compactMap { candidate -> (score: Int, amount: Double)? in
            let path = candidate.path.lowercased()
            guard path.contains("promo") || path.contains("promotion") || path.contains("grant") else { return nil }
            guard !path.contains("expires"), !path.contains("expiry"), !path.contains("date") else { return nil }
            guard let amount = moneyNumber(candidate.value, path: path) else { return nil }
            var score = 10
            if path.contains("amount") || path.contains("balance") || path.contains("credit") { score += 5 }
            if path.contains("initial") || path.contains("total") { score += 3 }
            if path.contains("used") || path.contains("spent") { score -= 8 }
            return (score, amount)
        }

        guard let rawBalance = balanceCandidates.max(by: { $0.score < $1.score })?.amount,
              let rawTotal = promotionalCandidates.max(by: { $0.score < $1.score })?.amount else { return nil }
        let balance = normalizedDollarAmount(rawBalance)
        let total = normalizedDollarAmount(rawTotal)
        guard total > 0 else { return nil }

        let expiration = values.first { candidate in
            let path = candidate.path.lowercased()
            return path.contains("expires") || path.contains("expiration") || path.contains("expiry")
        }.flatMap { expirationDescription($0.value) }

        return QuotaWindow(
            id: "claude-primary",
            title: AppConstants.claudeDefaultWindowTitle,
            usedFraction: nil,
            periodLabel: "点数余额",
            resetDescription: nil,
            state: .available,
            sourceDescription: "Claude 官方结构化点数数据",
            errorMessage: nil,
            updatedAt: now,
            creditBalance: balance,
            creditTotal: total,
            currencyCode: "USD",
            creditExpirationDescription: expiration ?? "点数有效期待同步"
        )
    }

    private static func scalarValues(in value: Any, path: String = "") -> [ScalarValue] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in
                scalarValues(in: child, path: path.isEmpty ? key : "\(path).\(key)")
            }
        }
        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, child in
                scalarValues(in: child, path: "\(path)[\(index)]")
            }
        }
        return [ScalarValue(path: path, value: value)]
    }

    private static func moneyNumber(_ value: Any, path: String) -> Double? {
        let raw: Double?
        if let number = value as? NSNumber {
            raw = number.doubleValue
        } else if let text = value as? String {
            let cleaned = text
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            raw = Double(cleaned)
        } else {
            raw = nil
        }
        guard let raw else { return nil }
        if path.contains("micro") { return raw / 1_000_000 }
        if path.contains("cent") { return raw / 100 }
        return raw
    }

    private static func normalizedDollarAmount(_ amount: Double) -> Double {
        // Some Claude billing responses expose integer cents without naming the
        // unit in the key (for example 10000 for the $100 promotional grant).
        // Values at or above 10,000 are outside the normal individual credit
        // balance range, so normalize them to dollars here.
        amount >= 10_000 ? amount / 100 : amount
    }

    private static func expirationDescription(_ value: Any) -> String? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let date = Date(timeIntervalSince1970: raw > 20_000_000_000 ? raw / 1000 : raw)
            return "有效期至 \(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))"
        }
        guard let text = value as? String, !text.isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: text) {
            return "有效期至 \(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))"
        }
        return "有效期至 \(text)"
    }

    private static func fableMetric(in dictionaries: [[String: Any]], now: Date) -> QuotaWindow? {
        for dictionary in dictionaries {
            guard let kind = dictionary["kind"] as? String,
                  kind.localizedCaseInsensitiveContains("weekly"),
                  let scope = dictionary["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any] else { continue }
            let name = (model["display_name"] ?? model["displayName"] ?? model["name"]) as? String ?? ""
            guard name.localizedCaseInsensitiveContains("fable") else { continue }
            if let metric = makeMetric(window: dictionary, period: "Fable 每周额度", now: now) {
                return metric
            }
        }
        return nil
    }

    private static func standardMetric(in dictionaries: [[String: Any]], now: Date) -> QuotaWindow? {
        for dictionary in dictionaries {
            if let weekly = dictionary["seven_day"] as? [String: Any]
                ?? dictionary["sevenDay"] as? [String: Any],
               let metric = makeMetric(window: weekly, period: "每周额度", now: now) {
                return metric
            }
        }
        for dictionary in dictionaries {
            if let session = dictionary["five_hour"] as? [String: Any]
                ?? dictionary["fiveHour"] as? [String: Any],
               let metric = makeMetric(window: session, period: "5 小时额度", now: now) {
                return metric
            }
        }
        return nil
    }

    private static func makeMetric(window: [String: Any], period: String, now: Date) -> QuotaWindow? {
        guard let percent = number(window["utilization"] ?? window["percent"] ?? window["usedPercent"] ?? window["used_percent"]) else {
            return nil
        }
        let resetValue = window["resets_at"] ?? window["resetsAt"]
        let reset = resetDate(resetValue)
        return QuotaWindow(
            id: "claude-primary",
            title: AppConstants.claudeDefaultWindowTitle,
            usedFraction: max(0, min(1, percent / 100)),
            periodLabel: period,
            resetDescription: reset.map { "\($0.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN")))) 重置" },
            state: .available,
            sourceDescription: "Claude 官方结构化使用量",
            errorMessage: nil,
            updatedAt: now
        )
    }

    private static func allDictionaries(in value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if let dictionary = value as? [String: Any] {
            result.append(dictionary)
            for child in dictionary.values { result.append(contentsOf: allDictionaries(in: child)) }
        } else if let array = value as? [Any] {
            for child in array { result.append(contentsOf: allDictionaries(in: child)) }
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func resetDate(_ value: Any?) -> Date? {
        if let number = number(value) {
            return Date(timeIntervalSince1970: number > 20_000_000_000 ? number / 1000 : number)
        }
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}
