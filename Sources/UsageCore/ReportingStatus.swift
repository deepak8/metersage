import Foundation

public enum DailyHistoryState: Sendable, Equatable {
    case notReported, unsupported, noRecords, reported, failed
}

public enum ReportAge {
    public static func compact(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

public struct ProviderHealth: Sendable {
    public enum Status: Sendable, Equatable { case neutral, healthy, attention }
    public let status: Status
    public let text: String
    public let recoveryProvider: Provider?

    public init(enabled: Set<Provider>, readings: [Reading], messages: [Provider: String], refreshing: Bool, now: Date = .now) {
        let ordered = Provider.allCases.filter { enabled.contains($0) }
        let available = ordered.filter { provider in
            guard messages[provider] == nil, let reading = readings.first(where: { $0.provider == provider }), !reading.isStale(at: now) else { return false }
            return reading.quotas.contains { $0.resetsAt.map { $0 > now } ?? true }
        }
        let errors = ordered.filter { messages[$0] != nil }
        let missing = ordered.filter { !available.contains($0) }
        recoveryProvider = errors.first ?? (refreshing ? nil : missing.first)
        if ordered.isEmpty {
            status = .neutral; text = "Connect an account to begin"
        } else if available.count == ordered.count {
            status = .healthy; text = "\(available.count) of \(ordered.count) providers available"
        } else if refreshing && errors.isEmpty {
            status = .neutral; text = "Checking providers…"
        } else {
            status = .attention; text = "\(available.count) of \(ordered.count) providers available"
        }
    }
}

public struct HistoryAvailability: Sendable {
    public let title: String
    public let detail: String
    public let canRetry: Bool

    public init(enabled: Set<Provider>, codexState: DailyHistoryState, refreshing: Bool) {
        canRetry = enabled.contains(.codex) && !refreshing && (codexState == .failed || codexState == .notReported)
        if enabled.contains(.codex) && refreshing {
            title = "Checking daily history…"
            detail = "Allowances and daily token totals are reported separately."
        } else if enabled.contains(.codex) {
            switch codexState {
            case .unsupported:
                title = "Daily history isn’t supported by this Codex CLI"
                detail = "Account allowances still work. Claude and Antigravity integrations do not report daily totals."
            case .failed:
                title = "Daily history couldn’t be refreshed"
                detail = "Retry the report. Your available allowance readings remain visible."
            case .noRecords, .reported:
                title = "No daily totals in the last 7 days"
                detail = "Codex returned no totals for this period. Claude context snapshots are not daily usage."
            case .notReported:
                title = "Daily totals haven’t been reported"
                detail = "Check Codex reporting. Claude and Antigravity integrations do not provide daily token history."
            }
        } else {
            title = "Daily history isn’t available from these connections"
            detail = enabled.isEmpty ? "Connect an account to check its reporting capabilities." : "Claude reports session metrics; Antigravity reports allowances. Neither integration provides daily totals."
        }
    }
}
