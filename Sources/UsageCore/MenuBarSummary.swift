import Foundation

/// A single independently measured window in the compact status strip.
public struct MenuBarLimitSummary: Sendable {
    public enum Tone: Sendable, Equatable { case normal, low, cached, unavailable }
    public let text: String
    public let tone: Tone

    public init(provider: Provider, window: AllowanceWindow, reading: Reading?, threshold: Double = 20, now: Date = .now) {
        guard let reading, !reading.isStale(at: now) || provider == .claude,
              let quota = reading.quota(for: window, at: now) else {
            text = "—"; tone = .unavailable
            return
        }
        let cached = reading.isStale(at: now)
        text = "\(Int(quota.remaining))%" + (cached ? "*" : "")
        tone = cached ? .cached : (quota.remaining <= threshold ? .low : .normal)
    }
}

/// Numbers represent remaining quota, never token consumption or a default zero.
/// Claude retains stale readings with an explicit marker.
public struct MenuBarSummary: Sendable {
    public var text: String
    public var explanation: String
    public var needsAttention: Bool

    public init(provider: Provider, reading: Reading?, error: String? = nil, threshold: Double = 20, now: Date = .now) {
        let prefix = provider.name + ": "
        guard let reading else {
            text = "—"; explanation = prefix + (error ?? "Not connected or usage unavailable.")
            needsAttention = error != nil
            return
        }
        let stale = reading.isStale(at: now)
        guard !stale || provider == .claude else {
            text = "—"; explanation = prefix + "Reading is stale. Refresh or use the official CLI to send new metrics."
            needsAttention = true
            return
        }
        let active = reading.quotas.filter { $0.resetsAt.map { $0 > now } ?? true }
        guard let quota = active.min(by: { $0.remaining < $1.remaining }) else {
            text = "—"
            explanation = prefix + (provider == .claude && !reading.quotas.isEmpty
                ? "Previously reported windows have reset. Refresh to request new account usage."
                : "Remaining allowance unavailable. " + reading.scope)
            needsAttention = error != nil
            return
        }
        // Floor rather than round so a small non-zero usage never displays 100%.
        let percentage = "\(Int(quota.remaining))%"
        text = percentage + (stale ? "*" : "")
        // Each window has its own minimum across model groups. The weekly and
        // 5-hour minima may belong to different groups (notably Antigravity).
        let weekly = reading.quota(for: .weekly, at: now)
        let fiveHour = reading.quota(for: .fiveHour, at: now)
        if weekly != nil || fiveHour != nil {
            func value(_ window: Quota?) -> String {
                window.map { "\(Int($0.remaining))%" + (stale ? "*" : "") } ?? "—"
            }
            text = "w\(value(weekly)) 5h\(value(fiveHour))"
        }
        if stale {
            let formatter = RelativeDateTimeFormatter()
            let age = formatter.localizedString(for: reading.observedAt, relativeTo: now)
            explanation = prefix + "Last reported " + percentage + " remaining · " + quota.label
                + ". Reported " + age + ". * Cached, not live; Refresh requests updated account usage."
        } else {
            explanation = prefix + percentage + " remaining · " + quota.label
        }
        if let weekly { explanation += ". Weekly: \(Int(weekly.remaining))% remaining · \(weekly.label)" }
        if let fiveHour { explanation += ". 5-hour: \(Int(fiveHour.remaining))% remaining · \(fiveHour.label)" }
        if let error { explanation += ". " + error }
        needsAttention = stale || quota.remaining <= threshold || error != nil
    }
}
