import Foundation
import Testing
import UsageCore
@testable import MeterSage

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}
private actor Reports {
    var count = 0
    func read(now: Date) -> Reading {
        count += 1
        return Reading(provider: .claude, quotas: [.init(label: "Weekly", usedPercent: Double(count))],
                       observedAt: count == 1 ? now.addingTimeInterval(-600) : now,
                       quotaIsCached: count == 1, scope: "fixture")
    }
}

@Test @MainActor func manualRefreshRetriesCachedClaudeWhileAutomaticChecksBackOff() async {
    let clock = TestClock(), reports = Reports()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = MonitorStore(startAutomatically: false, defaults: defaults, clock: { clock.now() },
                             claudeReader: { await reports.read(now: clock.now()) })
    store.enabled = [.claude]
    await store.refresh(manual: false)
    let captured = store.reading(.claude)?.observedAt
    #expect(await reports.count == 1)
    #expect(store.reading(.claude)?.quotaIsCached == true)
    clock.advance(60)
    await store.refresh(manual: false)
    #expect(await reports.count == 1)
    #expect(store.reading(.claude)?.observedAt == captured)
    await store.refresh() // Explicit click must bypass the soft automatic delay.
    #expect(await reports.count == 2)
    #expect(store.reading(.claude)?.quotaIsCached == false)
    #expect(store.messages[.claude] == nil)
    #expect(store.lastRefreshSummary == nil)
    await store.refresh()
    #expect(await reports.count == 2)
    #expect(store.lastRefreshSummary?.contains("not checked") == true)
    clock.advance(300)
    await store.refresh(manual: false)
    #expect(await reports.count == 3)
}

@Test func claudeRefreshPolicyHonorsExplicitRateLimitForManualAndAutomaticChecks() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let deadline = now.addingTimeInterval(1200)
    var policy = ClaudeRefreshPolicy()
    policy.begin(at: now)
    policy.failed(ClaudeUsageError.rateLimitedUntil(deadline), at: now)
    #expect(policy.deferredUntil(manual: true, now: now.addingTimeInterval(60)) == deadline)
    #expect(policy.deferredUntil(manual: false, now: now.addingTimeInterval(600)) == deadline)
    #expect(policy.deferredUntil(manual: true, now: deadline) == nil)
}

@Test func claudeParsesRetryDeadlineAlongsideCachedReadingWithoutChangingCaptureAge() throws {
    let zone = TimeZone(secondsFromGMT: 0)!
    let now = ISO8601DateFormatter().date(from: "2026-11-18T23:50:00Z")!
    let text = """
    Current session
    4% used
    Current week (all models)
    25% used
    Showing last-known usage from 9 minutes ago
    rate limited until 12:14am (GMT)
    """
    let reading = try ClaudeUsageReport.parse(text, now: now, timeZone: zone)
    #expect(reading.observedAt == now.addingTimeInterval(-540))
    #expect(reading.quotaRetryAfter == now.addingTimeInterval(24 * 60))
    var policy = ClaudeRefreshPolicy()
    policy.begin(at: now)
    policy.received(reading, at: now)
    #expect(policy.deferredUntil(manual: true, now: now.addingTimeInterval(60)) == reading.quotaRetryAfter)
    #expect(ClaudeUsageReport.retryAfter(in: "rate limited until 18:14", now: now, timeZone: zone) == now.addingTimeInterval(18 * 3600 + 24 * 60))
}

@Test func cachedClaudeReportWithUndatedRateLimitBacksOffRatherThanHammering() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reading = try ClaudeUsageReport.parse("Current session\n4% used\nShowing last-known usage from 9 minutes ago\nUsage endpoint is rate limited", now: now)
    #expect(reading.quotaRetryAfter == now.addingTimeInterval(900))
    #expect(reading.observedAt == now.addingTimeInterval(-540))
}
