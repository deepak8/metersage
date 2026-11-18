import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Identifiable {
    case codex, claude, antigravity
    public var id: String { rawValue }
    public var name: String {
        switch self { case .codex: "Codex"; case .claude: "Claude"; case .antigravity: "Antigravity" }
    }
    public var plan: String {
        switch self { case .codex: "Plus"; case .claude: "Pro"; case .antigravity: "AI Pro" }
    }
}

public struct Quota: Codable, Sendable, Equatable {
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var bucketID: String?
    public var resetDescription: String?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public init(label: String, usedPercent: Double, resetsAt: Date? = nil, bucketID: String? = nil, resetDescription: String? = nil) {
        self.label = label; self.usedPercent = usedPercent; self.resetsAt = resetsAt
        self.bucketID = bucketID
        self.resetDescription = resetDescription
    }
}

public struct Reading: Codable, Sendable, Identifiable {
    public var id: Provider { provider }
    public var provider: Provider
    public var account: String?
    public var plan: String?
    public var quotas: [Quota]
    public var unavailableQuotas: [String]?
    public var tokens: Int?
    public var estimatedCost: Double?
    public var observedAt: Date
    public var metricsObservedAt: Date?
    public var quotaIsCached: Bool?
    public var scope: String
    public var limitingQuota: Quota? { quotas.min { $0.remaining < $1.remaining } }
    public func isStale(at now: Date = .now) -> Bool { quotaIsCached == true || now.timeIntervalSince(observedAt) > 900 }
    /// Session metrics and account quotas are independent observations.
    public func mergingClaudeMetrics(_ session: Reading?) -> Reading {
        guard provider == .claude, let session, session.provider == .claude else { return self }
        var result = self
        result.tokens = session.tokens; result.estimatedCost = session.estimatedCost
        result.metricsObservedAt = session.metricsObservedAt ?? session.observedAt
        return result
    }
    public init(provider: Provider, account: String? = nil, plan: String? = nil, quotas: [Quota] = [], unavailableQuotas: [String]? = nil, tokens: Int? = nil, estimatedCost: Double? = nil, observedAt: Date = .now, metricsObservedAt: Date? = nil, quotaIsCached: Bool? = nil, scope: String) {
        self.provider = provider; self.account = account; self.plan = plan; self.quotas = quotas
        self.unavailableQuotas = unavailableQuotas
        self.tokens = tokens; self.estimatedCost = estimatedCost; self.observedAt = observedAt; self.scope = scope
        self.metricsObservedAt = metricsObservedAt; self.quotaIsCached = quotaIsCached
    }
}

public struct UsageDay: Codable, Sendable, Identifiable {
    public var id: String { "\(date.timeIntervalSince1970)-\(provider.rawValue)" }
    public var date: Date
    public var provider: Provider
    public var tokens: Int
    public init(date: Date, provider: Provider, tokens: Int) { self.date = date; self.provider = provider; self.tokens = tokens }
}

/// Keep only the latest session snapshot. Context tokens are not daily consumption;
/// session cost is cumulative. No prompts or credentials enter this schema.
public struct ClaudeSnapshot: Codable, Sendable {
    public var sessionID: String
    public var observedAt: Date
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cost: Double?
    public var quotas: [Quota]
    public var tokens: Int? {
        guard inputTokens != nil || outputTokens != nil else { return nil }
        return (inputTokens ?? 0) + (outputTokens ?? 0)
    }
    public static func parse(_ data: Data, now: Date = .now) throws -> ClaudeSnapshot {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let id = root["session_id"] as? String, !id.isEmpty else { throw SnapshotError.missingSession }
        let context = root["context_window"] as? [String: Any] ?? [:]
        let cost = root["cost"] as? [String: Any] ?? [:]
        let limits = root["rate_limits"] as? [String: Any] ?? [:]
        let quotas = [("five_hour", "5-hour"), ("seven_day", "Weekly")].compactMap { key, label -> Quota? in
            guard let item = limits[key] as? [String: Any], let used = item["used_percentage"] as? Double, used.isFinite else { return nil }
            let reset = (item["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return Quota(label: label, usedPercent: used, resetsAt: reset)
        }
        return ClaudeSnapshot(sessionID: id, observedAt: now,
                              inputTokens: context["total_input_tokens"] as? Int,
                              outputTokens: context["total_output_tokens"] as? Int,
                              cost: cost["total_cost_usd"] as? Double, quotas: quotas)
    }
    public enum SnapshotError: Error { case missingSession }
}

public enum UsageLogic {
    public static func minimumRemaining(_ readings: [Reading], now: Date = .now) -> Double? {
        readings.filter { !$0.isStale(at: now) }.compactMap { $0.limitingQuota?.remaining }.min()
    }
    public static func demo(now: Date = .now) -> [Reading] {
        [Reading(provider: .codex, account: "codex@example.com", plan: "Plus",
                 quotas: [Quota(label: "5-hour", usedPercent: 58, resetsAt: now.addingTimeInterval(8100)),
                          Quota(label: "Weekly", usedPercent: 36, resetsAt: now.addingTimeInterval(172800))],
                 tokens: 232480, estimatedCost: 0.93, observedAt: now.addingTimeInterval(-60), scope: "Sample data · Today"),
         Reading(provider: .claude, account: "claude@example.com", plan: "Pro",
                 quotas: [Quota(label: "5-hour", usedPercent: 88, resetsAt: now.addingTimeInterval(2880)),
                          Quota(label: "Weekly", usedPercent: 32, resetsAt: now.addingTimeInterval(172800))],
                 tokens: 876220, estimatedCost: 3.50, observedAt: now.addingTimeInterval(-60), scope: "Sample data · Current context / session cost"),
         Reading(provider: .antigravity, plan: "AI Pro",
                 quotas: [Quota(label: "Gemini Models · 5-hour", usedPercent: 24, resetsAt: now.addingTimeInterval(9600)),
                          Quota(label: "Gemini Models · Weekly", usedPercent: 8, resetsAt: now.addingTimeInterval(345600)),
                          Quota(label: "Claude/GPT · 5-hour", usedPercent: 45, resetsAt: now.addingTimeInterval(7200)),
                          Quota(label: "Claude/GPT · Weekly", usedPercent: 12, resetsAt: now.addingTimeInterval(259200))],
                 observedAt: now.addingTimeInterval(-60), scope: "Sample data · Account quota groups")]
    }
    public static func demoHistory(now: Date = .now) -> [UsageDay] {
        let calendar = Calendar.current
        return (0..<7).flatMap { index -> [UsageDay] in
            let day = calendar.date(byAdding: .day, value: index - 6, to: calendar.startOfDay(for: now))!
            return [UsageDay(date: day, provider: .codex, tokens: [72000, 96000, 81000, 54000, 70000, 116000, 144000][index]),
                    UsageDay(date: day, provider: .claude, tokens: [76000, 90000, 74000, 51000, 72000, 87000, 126000][index])]
        }
    }
}
