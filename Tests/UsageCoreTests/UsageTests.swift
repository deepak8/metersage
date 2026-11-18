import Foundation
import Testing
@testable import UsageCore

@Test func staleAndUnknownQuotasDoNotLookHealthy() {
    let now = Date()
    let stale = Reading(provider: .codex, quotas: [.init(label: "Weekly", usedPercent: 99)], observedAt: now.addingTimeInterval(-1000), scope: "test")
    let unknown = Reading(provider: .claude, scope: "test")
    #expect(UsageLogic.minimumRemaining([stale, unknown], now: now) == nil)
    let fresh = Reading(provider: .claude, quotas: [.init(label: "5h", usedPercent: 60), .init(label: "week", usedPercent: 95)], scope: "test")
    #expect(UsageLogic.minimumRemaining([stale, fresh], now: now) == 5)
}

@Test func statuslineExtractsOnlyKnownFieldsAndPreservesMissingTokens() throws {
    let data = Data(#"{"session_id":"session-a","rate_limits":{"five_hour":{"used_percentage":88,"resets_at":2000000000}},"prompt":"must never be saved","cost":{"total_cost_usd":1.25}}"#.utf8)
    let snapshot = try ClaudeSnapshot.parse(data)
    #expect(snapshot.tokens == nil)
    #expect(snapshot.quotas.first?.remaining == 12)
    let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!encoded.contains("must never be saved"))
}

@Test func remainingIsClampedAndMissingRateLimitsStayMissing() throws {
    #expect(Quota(label: "test", usedPercent: 120).remaining == 0)
    #expect(Quota(label: "test", usedPercent: -3).remaining == 100)
    let snapshot = try ClaudeSnapshot.parse(Data(#"{"session_id":"a","context_window":{"total_input_tokens":10,"total_output_tokens":20}}"#.utf8))
    #expect(snapshot.tokens == 30)
    #expect(snapshot.quotas.isEmpty)
}

@Test func menuBarUsesRemainingAndNeverInventsMissingQuota() {
    let now = Date()
    let reading = Reading(provider: .codex, quotas: [
        Quota(label: "5-hour", usedPercent: 24.2, resetsAt: now.addingTimeInterval(300)),
        Quota(label: "Weekly", usedPercent: 90, resetsAt: now.addingTimeInterval(3000))
    ], observedAt: now, scope: "test")
    let summary = MenuBarSummary(provider: .codex, reading: reading, now: now)
    #expect(summary.text == "w10% 5h75%")
    #expect(summary.needsAttention)
    #expect(summary.explanation.contains("Weekly"))
    #expect(MenuBarSummary(provider: .antigravity, reading: nil, now: now).text == "—")
    let tokensOnly = Reading(provider: .claude, tokens: 1000, observedAt: now, scope: "test")
    #expect(MenuBarSummary(provider: .claude, reading: tokensOnly, now: now).text == "—")
}

@Test func menuBarSuppressesStaleAndExpiredWindows() {
    let now = Date()
    let stale = Reading(provider: .codex, quotas: [.init(label: "Weekly", usedPercent: 99)], observedAt: now.addingTimeInterval(-901), scope: "test")
    #expect(MenuBarSummary(provider: .codex, reading: stale, now: now).text == "—")
    let expired = Reading(provider: .codex, quotas: [
        .init(label: "Expired", usedPercent: 100, resetsAt: now.addingTimeInterval(-1)),
        .init(label: "Active", usedPercent: 20.1, resetsAt: now.addingTimeInterval(100))
    ], observedAt: now, scope: "test")
    #expect(MenuBarSummary(provider: .codex, reading: expired, now: now).text == "79%")
}

@Test func menuBarSeparatesWeeklyAndFiveHourMinimaAcrossModelGroups() {
    let now = Date()
    let reading = Reading(provider: .antigravity, quotas: [
        .init(label: "Gemini · Weekly", usedPercent: 13),
        .init(label: "Gemini · 5-hour", usedPercent: 2),
        .init(label: "Claude/GPT · Weekly", usedPercent: 9),
        .init(label: "Claude/GPT · 5-hour", usedPercent: 8),
        .init(label: "Old · 5-hour", usedPercent: 100, resetsAt: now.addingTimeInterval(-1))
    ], scope: "test")
    let summary = MenuBarSummary(provider: .antigravity, reading: reading, now: now)
    #expect(summary.text == "w87% 5h92%")
    #expect(summary.explanation.contains("5-hour: 92% remaining · Claude/GPT"))
    let exhausted = Reading(provider: .codex, quotas: [.init(label: "Weekly", usedPercent: 100), .init(label: "5-hour", usedPercent: 0)], scope: "test")
    #expect(MenuBarSummary(provider: .codex, reading: exhausted).text == "w0% 5h100%")
}

@Test func claudeIdleKeepsLastReportedPercentageWithoutMarkingItFresh() {
    let now = Date()
    let observed = now.addingTimeInterval(-1800)
    let reading = Reading(provider: .claude,
                          quotas: [.init(label: "5-hour", usedPercent: 18, resetsAt: now.addingTimeInterval(7200))],
                          observedAt: observed, scope: "Latest CLI session")
    let summary = MenuBarSummary(provider: .claude, reading: reading, now: now)
    #expect(summary.text == "w— 5h82%*")
    #expect(summary.needsAttention)
    #expect(summary.explanation.contains("Last reported"))
    #expect(summary.explanation.contains("Cached, not live"))
    #expect(reading.observedAt == observed)
    #expect(reading.isStale(at: now))
    #expect(UsageLogic.minimumRemaining([reading], now: now) == nil)
}

@Test func claudeCachedPercentageNeverCarriesAcrossAnExpiredWindow() {
    let now = Date()
    let old = now.addingTimeInterval(-1800)
    let expired = Quota(label: "5-hour", usedPercent: 99, resetsAt: now.addingTimeInterval(-1))
    let weekly = Quota(label: "Weekly", usedPercent: 15, resetsAt: now.addingTimeInterval(86400))
    let reading = Reading(provider: .claude, quotas: [expired, weekly], observedAt: old, scope: "test")
    #expect(MenuBarSummary(provider: .claude, reading: reading, now: now).text == "w85%* 5h—")
    let noActiveWindow = Reading(provider: .claude, quotas: [expired], observedAt: old, scope: "test")
    #expect(MenuBarSummary(provider: .claude, reading: noActiveWindow, now: now).text == "—")
}
