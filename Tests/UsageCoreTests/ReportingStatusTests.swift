import Foundation
import Testing
@testable import UsageCore

@Test func healthIncludesErrorsForProvidersWithoutAReading() {
    let good = Reading(provider: .codex, quotas: [.init(label: "Weekly", usedPercent: 13)], scope: "test")
    let health = ProviderHealth(enabled: [.codex, .claude], readings: [good], messages: [.claude: "Sign in"], refreshing: false)
    #expect(health.status == .attention)
    #expect(health.text == "1 of 2 providers available")
    #expect(health.recoveryProvider == .claude)
    let disconnected = ProviderHealth(enabled: [.codex], readings: [good], messages: [.claude: "Old error"], refreshing: false)
    #expect(disconnected.status == .healthy)
    #expect(disconnected.recoveryProvider == nil)
    let failed = ProviderHealth(enabled: [.claude], readings: [], messages: [.claude: "Sign in"], refreshing: true)
    #expect(failed.status == .attention && failed.text == "0 of 1 providers available")
}

@Test func healthDistinguishesLoadingStaleAndExpiredAllowances() {
    let now = Date()
    let loading = ProviderHealth(enabled: [.claude], readings: [], messages: [:], refreshing: true, now: now)
    #expect(loading.status == .neutral && loading.recoveryProvider == nil)
    let empty = ProviderHealth(enabled: [], readings: [], messages: [:], refreshing: false)
    #expect(empty.status == .neutral && empty.text == "Connect an account to begin")
    for reading in [
        Reading(provider: .claude, quotas: [.init(label: "Weekly", usedPercent: 0)], observedAt: now.addingTimeInterval(-1000), scope: "test"),
        Reading(provider: .claude, quotas: [.init(label: "5-hour", usedPercent: 0, resetsAt: now.addingTimeInterval(-1))], scope: "test"),
        Reading(provider: .claude, tokens: 42, scope: "test")
    ] {
        let health = ProviderHealth(enabled: [.claude], readings: [reading], messages: [:], refreshing: false, now: now)
        #expect(health.status == .attention && health.recoveryProvider == .claude)
    }
}

@Test func historyGuidanceDistinguishesUnsupportedEmptyAndFailed() {
    let unsupported = HistoryAvailability(enabled: [.codex], codexState: .unsupported, refreshing: false)
    #expect(unsupported.title.contains("isn’t supported") && !unsupported.canRetry)
    let empty = HistoryAvailability(enabled: [.codex], codexState: .noRecords, refreshing: false)
    #expect(empty.title == "No daily totals in the last 7 days" && !empty.canRetry)
    let failed = HistoryAvailability(enabled: [.codex], codexState: .failed, refreshing: false)
    #expect(failed.title.contains("couldn’t be refreshed") && failed.canRetry)
    let busy = HistoryAvailability(enabled: [.codex], codexState: .failed, refreshing: true)
    #expect(!busy.canRetry && busy.title == "Checking daily history…")
    let sessions = HistoryAvailability(enabled: [.claude, .antigravity], codexState: .failed, refreshing: false)
    #expect(!sessions.canRetry && sessions.detail.contains("Neither integration provides daily totals"))
}

@Test func compactReportAgeHandlesBoundariesAndFutureClockSkew() {
    let now = Date()
    #expect(ReportAge.compact(now.addingTimeInterval(30), now: now) == "just now")
    #expect(ReportAge.compact(now.addingTimeInterval(-27), now: now) == "27s ago")
    #expect(ReportAge.compact(now.addingTimeInterval(-120), now: now) == "2m ago")
    #expect(ReportAge.compact(now.addingTimeInterval(-7200), now: now) == "2h ago")
}
