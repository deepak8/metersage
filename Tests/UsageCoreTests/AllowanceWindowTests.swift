import Foundation
import Testing
@testable import UsageCore

@Test func overviewUsesStableWindowsAndIndependentGroupMinima() {
    let now = Date()
    let reading = Reading(provider: .antigravity, quotas: [
        .init(label: "Gemini · Weekly", usedPercent: 13),
        .init(label: "Gemini · 5-hour", usedPercent: 2),
        .init(label: "Claude/GPT · Weekly", usedPercent: 1),
        .init(label: "Claude/GPT · 5-hour", usedPercent: 40),
        .init(label: "Expired · 5-hour", usedPercent: 100, resetsAt: now.addingTimeInterval(-1))
    ], scope: "test")
    #expect(AllowanceWindow.allCases.map(\.title) == ["5-hour", "Weekly"])
    #expect(reading.quota(for: .fiveHour, at: now)?.label == "Claude/GPT · 5-hour")
    #expect(reading.quota(for: .fiveHour, at: now)?.remaining == 60)
    #expect(reading.quota(for: .weekly, at: now)?.remaining == 87)
    #expect(reading.quota(for: .weekly, at: now)?.label == "Gemini · Weekly")
    let missing = Reading(provider: .claude, quotas: [.init(label: "Weekly", usedPercent: 0)], scope: "test")
    #expect(missing.quota(for: .fiveHour, at: now) == nil)
    #expect(missing.quota(for: .weekly, at: now)?.remaining == 100)
}
