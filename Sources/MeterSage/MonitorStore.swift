import AppKit
import Observation
import ServiceManagement
import UserNotifications
import UsageCore

@MainActor @Observable final class MonitorStore {
    static let shared = MonitorStore()
    var demo: Bool { didSet { if !demo { Task { await refresh() } } } }
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
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var lastNetworkRefresh = Date.distantPast
    private var notified: Set<String> = []
    private var connectionEpoch: [Provider: Int] = [:]
    private var claudeRetryAfter = Date.distantPast

    init(startAutomatically: Bool = true) {
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        notifications = UserDefaults.standard.bool(forKey: "notifications")
        let threshold = UserDefaults.standard.double(forKey: "warningThreshold")
        warningThreshold = threshold == 0 ? 20 : threshold
        refreshMinutes = max(1, UserDefaults.standard.integer(forKey: "refreshMinutes"))
        if UserDefaults.standard.object(forKey: "refreshMinutes") == nil { refreshMinutes = 5 }
        enabled = Set((UserDefaults.standard.stringArray(forKey: "enabled") ?? []).compactMap(Provider.init(rawValue:)))
        notified = Set(UserDefaults.standard.stringArray(forKey: "notifiedWindows") ?? [])
        guard startAutomatically else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.demo else { return }
                self.refreshClaudeMetrics()
                if Date().timeIntervalSince(self.lastNetworkRefresh) >= Double(self.refreshMinutes * 60) { await self.refresh() }
            }
        }
        if !demo { Task { await refresh() } }
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
    }
    func refresh() async {
        guard !demo, !refreshing else { return }
        refreshing = true
        defer { refreshing = false; lastRefresh = .now; lastNetworkRefresh = .now }
        refreshClaudeMetrics()
        async let claude: Void = refreshClaude()
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
    private func refreshClaude() async {
        guard enabled.contains(.claude), Date.now >= claudeRetryAfter else { return }
        let epoch = connectionEpoch[.claude, default: 0]
        guard let executable = LocalFiles.executable("claude") else {
            messages[.claude] = "Install the official Claude Code CLI to connect."
            return
        }
        do {
            let reading = try await ClaudeUsageProbe.read(executable: executable)
            guard enabled.contains(.claude), !demo, connectionEpoch[.claude, default: 0] == epoch else { return }
            readings.removeAll { $0.provider == .claude }
            readings.append(reading.mergingClaudeMetrics(LocalFiles.latestClaude()))
            if reading.quotaIsCached == true {
                claudeRetryAfter = .now.addingTimeInterval(900)
                messages[.claude] = "Claude returned last-known usage. Retaining its capture age; checks resume in 15 minutes."
            } else { messages[.claude] = nil }
            await checkAlerts(reading)
        } catch {
            guard enabled.contains(.claude), !demo, connectionEpoch[.claude, default: 0] == epoch else { return }
            messages[.claude] = error.localizedDescription
            if let error = error as? ClaudeUsageError, case .rateLimited = error {
                claudeRetryAfter = .now.addingTimeInterval(900)
            }
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
