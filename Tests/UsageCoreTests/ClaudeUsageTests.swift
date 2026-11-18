import Foundation
import Testing
@testable import UsageCore

private let panel = """
Current session
21% 21% used
Resets 11:50pm (Asia/Calcutta)
Current week (all models)
16% 16% used
Resets Nov 20 at 7:30am (Asia/Calcutta)
What's contributing to your usage?
Approximate · sessions on this machine only
97% used
"""

@Test func claudeAccountPanelKeepsWindowsSeparateFromInsights() throws {
    let now = ISO8601DateFormatter().date(from: "2026-11-17T18:00:00Z")!
    let reading = try ClaudeUsageReport.parse(panel, now: now)
    #expect(reading.quotas.map(\.remaining) == [79, 84])
    #expect(reading.quotas.map(\.bucketID) == ["claude-5h", "claude-weekly"])
    #expect(reading.tokens == nil && reading.estimatedCost == nil)
    #expect(reading.observedAt == now && !reading.isStale(at: now))
    #expect(reading.quotas[0].resetsAt == ISO8601DateFormatter().date(from: "2026-11-17T18:20:00Z"))
    #expect(reading.quotas[1].resetsAt == ISO8601DateFormatter().date(from: "2026-11-20T02:00:00Z"))
}

@Test func claudeCachedPanelsPreserveAgeAndDoNotTriggerFreshAlerts() throws {
    let now = Date()
    let cached = try ClaudeUsageReport.parse(panel + "\nShowing last-known usage (updated 1h 30m ago)", now: now)
    #expect(cached.observedAt == now.addingTimeInterval(-5400))
    #expect(cached.quotaIsCached == true && cached.isStale(at: now))
    #expect(UsageLogic.minimumRemaining([cached], now: now) == nil)
    #expect(throws: ClaudeUsageError.self) { try ClaudeUsageReport.parse(panel + "\nShowing last-known usage") }
    #expect(throws: ClaudeUsageError.self) { try ClaudeUsageReport.parse(panel + "\nRefreshing…") }
    #expect(throws: ClaudeUsageError.self) { try ClaudeUsageReport.parse("Usage endpoint is rate limited") }
    #expect(throws: ClaudeUsageError.self) { try ClaudeUsageReport.parse("Please log in") }
    #expect(throws: ClaudeUsageError.self) { try ClaudeUsageReport.parse("97% used") }
}

@Test func claudeScopedLimitsAndZeroAreNotInventedOrCollapsed() throws {
    let reading = try ClaudeUsageReport.parse("Current session\n0% used\nCurrent week (Sonnet)\n4% remaining")
    #expect(reading.quotas.map(\.remaining) == [100, 4])
    #expect(reading.quotas[1].bucketID == "claude-weekly-sonnet")
    #expect(reading.quotas[0].resetsAt == nil)
}

@Test func terminalReplayReplacesOldValuesAndIgnoresKeyboardQueries() throws {
    let data = Data("Current session\r\n99% used\u{1b}[1G\u{1b}[2K21% used\r\n\u{1b}[?uCurrent week (all models)\r\n16% used".utf8)
    let rendered = TerminalScreen.render(data)
    #expect(!rendered.contains("99%"))
    #expect(try ClaudeUsageReport.parse(rendered).quotas.map(\.remaining) == [79, 84])
}

@Test func claudeMetricMergesNeverReplaceAccountQuotasOrTheirTimestamp() {
    let now = Date()
    let account = Reading(provider: .claude, quotas: [.init(label: "Weekly", usedPercent: 16)], observedAt: now, scope: "Account")
    let session = Reading(provider: .claude, quotas: [.init(label: "Weekly", usedPercent: 1)], tokens: 123, estimatedCost: 0.5,
                          observedAt: now.addingTimeInterval(-3600), scope: "Session")
    let merged = account.mergingClaudeMetrics(session)
    #expect(merged.quotas.first?.remaining == 84)
    #expect(merged.observedAt == now && merged.metricsObservedAt == session.observedAt)
    #expect(merged.tokens == 123 && merged.estimatedCost == 0.5)
    #expect(merged.scope == "Account")
}

@Test func claudeResetBoundaryDoesNotMoveExpiredWindowsToTomorrow() throws {
    let iso = ISO8601DateFormatter()
    let zone = TimeZone(identifier: "Asia/Calcutta")!
    let now = iso.date(from: "2026-11-17T18:20:30Z")!
    let reset = ClaudeUsageReport.parseReset("Resets 11:50pm (Asia/Calcutta)", now: now, timeZone: zone)
    #expect(reset == iso.date(from: "2026-11-17T18:20:00Z"))
    let overnight = ClaudeUsageReport.parseReset("Resets 1:00am (Asia/Calcutta)", now: now, timeZone: zone)
    #expect(overnight == iso.date(from: "2026-11-17T19:30:00Z"))
    let cached = try ClaudeUsageReport.parse(panel + "\nShowing last-known usage (updated 1h ago)", now: now)
    #expect(cached.quotas[0].resetsAt == reset)
    #expect(MenuBarSummary(provider: .claude, reading: cached, now: now).text == "w84%* 5h—")
}
