import AppKit
import Observation
import ServiceManagement
import UserNotifications
import UsageCore

@MainActor @Observable final class MonitorStore {
    static let shared = MonitorStore()
    var demo: Bool { didSet { if !demo { Task { await refresh(manual: false) } } } }
    var readings: [Reading] = []
    var days: [UsageDay] = []
    var codexHistoryState: DailyHistoryState = .notReported
    var messages: [Provider: String] = [:]
    var refreshing = false
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var notifications: Bool { didSet { defaults.set(notifications, forKey: "notifications") } }
    var warningThreshold: Double { didSet { defaults.set(warningThreshold, forKey: "warningThreshold") } }
    var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") } }
    var enabled: Set<Provider> = []
    var lastRefresh: Date?
    private let defaults: UserDefaults
    private var timer: Timer?
    private var lastNetworkRefresh = Date.distantPast
    private var notified: Set<String> = []
    private var connectionEpoch: [Provider: Int] = [:]
    private var claudeRefreshPolicy = ClaudeRefreshPolicy()
    var claudeRefreshNote: String?
    var lastRefreshSummary: String?
    private let clock: @Sendable () -> Date
    private let claudeReader: @Sendable () async throws -> Reading

    init(startAutomatically: Bool = true,
         defaults: UserDefaults = .standard,
         clock: @escaping @Sendable () -> Date = { .now },
         claudeReader: @escaping @Sendable () async throws -> Reading = {
             guard let executable = LocalFiles.executable("claude") else {
                 throw NSError(domain: "MeterSage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Install the official Claude Code CLI to connect."])
             }
             return try await ClaudeUsageProbe.read(executable: executable)
         }) {
        self.defaults = defaults
        self.clock = clock
        self.claudeReader = claudeReader
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        appearance = defaults.string(forKey: "appearance") ?? "system"
        notifications = defaults.bool(forKey: "notifications")
        let threshold = defaults.double(forKey: "warningThreshold")
        warningThreshold = threshold == 0 ? 20 : threshold
        refreshMinutes = max(1, defaults.integer(forKey: "refreshMinutes"))
        if defaults.object(forKey: "refreshMinutes") == nil { refreshMinutes = 5 }
        enabled = Set((defaults.stringArray(forKey: "enabled") ?? []).compactMap(Provider.init(rawValue:)))
        notified = Set(defaults.stringArray(forKey: "notifiedWindows") ?? [])
        guard startAutomatically else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.demo else { return }
                self.refreshClaudeMetrics()
                if Date().timeIntervalSince(self.lastNetworkRefresh) >= Double(self.refreshMinutes * 60) { await self.refresh(manual: false) }
            }
        }
        if !demo { Task { await refresh(manual: false) } }
    }
    var visibleReadings: [Reading] { demo ? UsageLogic.demo() : readings }
    var visibleDays: [UsageDay] { demo ? UsageLogic.demoHistory() : days }
    var historyAvailability: HistoryAvailability {
        HistoryAvailability(enabled: enabled, codexState: codexHistoryState, refreshing: refreshing)
    }
    var minimum: Double? { UsageLogic.minimumRemaining(visibleReadings) }
    var menuSymbol: String {
        if let minimum, minimum <= warningThreshold { return "exclamationmark.triangle.fill" }
        return "chart.bar.fill"
    }
    func reading(_ provider: Provider) -> Reading? { visibleReadings.first { $0.provider == provider } }
    func connect(_ provider: Provider) {
        guard !demo else { return }
        enabled.insert(provider)
        defaults.set(enabled.map(\.rawValue), forKey: "enabled")
        Task { await refresh() }
    }
    func disconnect(_ provider: Provider) {
        guard !demo else { return }
        enabled.remove(provider)
        connectionEpoch[provider, default: 0] += 1
        defaults.set(enabled.map(\.rawValue), forKey: "enabled")
        readings.removeAll { $0.provider == provider }
        days.removeAll { $0.provider == provider }
        if provider == .codex { codexHistoryState = .notReported }
        messages[provider] = nil
        if provider == .claude { claudeRefreshNote = nil; claudeRefreshPolicy = ClaudeRefreshPolicy() }
    }
    func refresh(manual: Bool = true) async {
        guard !demo, !refreshing else { return }
        refreshing = true
        defer { refreshing = false; lastRefresh = .now; lastNetworkRefresh = .now }
        lastRefreshSummary = nil
        refreshClaudeMetrics()
        async let claude: Void = refreshClaude(manual: manual)
        async let codex: Void = refreshCodex()
        async let antigravity: Void = refreshAntigravity()
        _ = await (claude, codex, antigravity)
    }
    private func refreshCodex() async {
        guard enabled.contains(.codex) else { return }
        let epoch = connectionEpoch[.codex, default: 0]
        guard let executable = LocalFiles.executable("codex") else {
            messages[.codex] = "Install the official Codex CLI to connect."
            codexHistoryState = .failed
            return
        }
        do {
            let result = try await Task.detached { try CodexIntegration.read(executable: executable) }.value
            guard enabled.contains(.codex), !demo, connectionEpoch[.codex, default: 0] == epoch else { return }
            readings.removeAll { $0.provider == .codex }; readings.append(result.reading)
            days.removeAll { $0.provider == .codex }; days.append(contentsOf: result.days)
            codexHistoryState = result.historyState
            messages[.codex] = nil
            await checkAlerts(result.reading)
        } catch {
            if enabled.contains(.codex), !demo, connectionEpoch[.codex, default: 0] == epoch {
                messages[.codex] = error.localizedDescription
                codexHistoryState = .failed
            }
        }
    }
    private func refreshAntigravity() async {
        guard enabled.contains(.antigravity) else { return }
        let epoch = connectionEpoch[.antigravity, default: 0]
        guard let executable = LocalFiles.executable("agy") else {
            messages[.antigravity] = "Install the official Antigravity CLI (agy) to connect."
            return
        }
        do {
            let reading = try await AntigravityIntegration.read(executable: executable)
            guard enabled.contains(.antigravity), !demo, connectionEpoch[.antigravity, default: 0] == epoch else { return }
            readings.removeAll { $0.provider == .antigravity }; readings.append(reading)
            messages[.antigravity] = nil
            await checkAlerts(reading)
        } catch {
            if enabled.contains(.antigravity), !demo, connectionEpoch[.antigravity, default: 0] == epoch { messages[.antigravity] = error.localizedDescription }
        }
    }
    private func refreshClaudeMetrics() {
        guard enabled.contains(.claude) else { return }
        guard let session = LocalFiles.latestClaude() else { return }
        if let index = readings.firstIndex(where: { $0.provider == .claude }) {
            readings[index] = readings[index].mergingClaudeMetrics(session)
        } else { readings.append(session) }
    }
    private func refreshClaude(manual: Bool) async {
        guard enabled.contains(.claude) else { return }
        if let until = claudeRefreshPolicy.deferredUntil(manual: manual, now: clock()) {
            let time = until.formatted(.dateTime.hour().minute().second())
            claudeRefreshNote = "Claude check deferred until \(time). Displayed usage keeps its original capture time."
            if manual { lastRefreshSummary = "Claude not checked · retry at \(time)" }
            return
        }
        let epoch = connectionEpoch[.claude, default: 0]
        claudeRefreshPolicy.begin(at: clock())
        do {
            let reading = try await claudeReader()
            guard enabled.contains(.claude), !demo, connectionEpoch[.claude, default: 0] == epoch else { return }
            claudeRefreshPolicy.received(reading, at: clock())
            readings.removeAll { $0.provider == .claude }
            readings.append(reading.mergingClaudeMetrics(LocalFiles.latestClaude()))
            messages[.claude] = nil
            if reading.quotaIsCached == true {
                let next = max(claudeRefreshPolicy.nextAutomaticCheck, claudeRefreshPolicy.rateLimitedUntil ?? .distantPast)
                claudeRefreshNote = "Claude returned cached usage. Next automatic check: \(next.formatted(date: .omitted, time: .shortened)). Refresh can retry sooner unless Claude is rate limited."
                lastRefreshSummary = "Claude returned cached usage"
            } else {
                claudeRefreshNote = "Checked \(clock().formatted(date: .omitted, time: .shortened)) · automatic checks at least 5 minutes apart."
            }
            await checkAlerts(reading)
        } catch {
            guard enabled.contains(.claude), !demo, connectionEpoch[.claude, default: 0] == epoch else { return }
            claudeRefreshPolicy.failed(error, at: clock())
            messages[.claude] = error.localizedDescription
            let next = max(claudeRefreshPolicy.nextAutomaticCheck, claudeRefreshPolicy.rateLimitedUntil ?? .distantPast)
            claudeRefreshNote = "Last check failed. Next automatic check: \(next.formatted(date: .omitted, time: .shortened))."
            lastRefreshSummary = "Claude refresh failed · see details"
        }
    }
    func requestNotifications() async {
        do {
            notifications = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch { notifications = false }
    }
    private func checkAlerts(_ reading: Reading) async {
        guard notifications, !demo, !reading.isStale() else { return }
        for quota in reading.quotas {
            guard let reset = quota.resetsAt, reset > .now else { continue }
            for threshold in Set([warningThreshold, min(10, warningThreshold)]).sorted() where quota.remaining <= threshold {
                let key = "\(reading.provider.rawValue)-\(quota.bucketID ?? quota.label)-\(reset.timeIntervalSince1970)-\(threshold)"
                guard !notified.contains(key) else { continue }
                notified.insert(key)
                let content = UNMutableNotificationContent()
                content.title = "\(reading.provider.name) allowance is running low"
                content.body = "\(Int(quota.remaining))% remaining in your \(quota.label.lowercased()) window."
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
                // A single notification covers all thresholds crossed in this update.
                for crossed in [warningThreshold, min(10, warningThreshold)] where quota.remaining <= crossed {
                    notified.insert("\(reading.provider.rawValue)-\(quota.bucketID ?? quota.label)-\(reset.timeIntervalSince1970)-\(crossed)")
                }
                defaults.set(Array(notified), forKey: "notifiedWindows")
                break
            }
        }
    }
    func clearLocalHistory() {
        days = []
        readings.removeAll { $0.provider == .claude }
        try? FileManager.default.removeItem(at: LocalFiles.bridge)
        // Provider-reported Codex history can return on the next explicit refresh.
    }
}
