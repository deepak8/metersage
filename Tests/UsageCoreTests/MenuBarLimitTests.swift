import Foundation
import Testing
@testable import UsageCore

@Test func stackedLimitsWarnIndependentlyAndKeepMissingDistinctFromZero() {
    let reading = Reading(provider: .claude, quotas: [.init(label: "Weekly", usedPercent: 13), .init(label: "5-hour", usedPercent: 90)], scope: "test")
    let weekly = MenuBarLimitSummary(provider: .claude, window: .weekly, reading: reading, threshold: 20)
    let fiveHour = MenuBarLimitSummary(provider: .claude, window: .fiveHour, reading: reading, threshold: 20)
    #expect(weekly.text == "87%" && weekly.tone == .normal)
    #expect(fiveHour.text == "10%" && fiveHour.tone == .low)
    let missing = MenuBarLimitSummary(provider: .claude, window: .weekly, reading: nil)
    #expect(missing.text == "—" && missing.tone == .unavailable)
}

@Test func stackedLimitsRespectCacheAgeResetExpiryAndProviderStaleness() {
    let now = Date()
    var reading = Reading(provider: .claude, quotas: [
        .init(label: "Weekly", usedPercent: 0, resetsAt: now.addingTimeInterval(600)),
        .init(label: "5-hour", usedPercent: 100, resetsAt: now.addingTimeInterval(-1))
    ], observedAt: now.addingTimeInterval(-1800), scope: "test")
    let cached = MenuBarLimitSummary(provider: .claude, window: .weekly, reading: reading, now: now)
    #expect(cached.text == "100%*" && cached.tone == .cached)
    #expect(MenuBarLimitSummary(provider: .claude, window: .fiveHour, reading: reading, now: now).text == "—")
    reading.provider = .codex
    #expect(MenuBarLimitSummary(provider: .codex, window: .weekly, reading: reading, now: now).tone == .unavailable)
}
