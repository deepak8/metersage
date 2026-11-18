import Foundation
import Testing
import UsageCore
@testable import MeterSage

private func fixture(_ script: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("codex-fixture")
    try Data(("#!/bin/sh\n" + script).utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
}

@Test func codexProtocolReadsMultipleWindowsAndToleratesUnsupportedDailyUsage() throws {
    let executable = try fixture(#"""
    IFS= read -r initialize
    printf '%s\n' '{"id":1,"result":{}}'
    IFS= read -r initialized
    IFS= read -r account
    printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"test@example.com","planType":"plus"}}}'
    IFS= read -r limits
    printf '%s\n' '{"method":"account/updated","params":{}}'
    printf '%s\n' '{"id":3,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":58,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":91,"windowDurationMins":10080,"resetsAt":2000200000}}}}}'
    IFS= read -r usage
    printf '%s\n' '{"id":4,"error":{"code":-32601,"message":"unsupported"}}'
    """#)
    defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
    let result = try CodexIntegration.read(executable: executable)
    #expect(result.reading.account == "test@example.com")
    #expect(result.reading.quotas.count == 2)
    #expect(result.reading.limitingQuota?.remaining == 9)
    #expect(result.reading.limitingQuota?.label == "Weekly")
    #expect(result.reading.tokens == nil)
    #expect(result.days.isEmpty)
    #expect(result.historyState == .unsupported)
}

@Test func codexSeparatesEmptyMissingFailedAndReportedHistory() throws {
    let reports: [(String, DailyHistoryState)] = [
        (#"{"id":4,"result":{"dailyUsageBuckets":[]}}"#, .noRecords),
        (#"{"id":4,"result":{}}"#, .notReported),
        (#"{"id":4,"error":{"code":-32000,"message":"temporary failure"}}"#, .failed),
        (#"{"id":4,"result":{"dailyUsageBuckets":[{"startDate":"2026-11-18","tokens":12}]}}"#, .reported)
    ]
    for (report, expected) in reports {
        let executable = try fixture("""
        IFS= read -r initialize
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r account
        printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt"}}}'
        IFS= read -r limits
        printf '%s\\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300}}}}'
        IFS= read -r usage
        printf '%s\\n' '\(report)'
        """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let result = try CodexIntegration.read(executable: executable)
        #expect(result.historyState == expected)
        #expect(result.reading.quotas.first?.remaining == 90)
        #expect(result.days.count == (expected == .reported ? 1 : 0))
    }
}

@Test func codexRejectsApiKeyAccountsForSubscriptionMonitoring() throws {
    let executable = try fixture(#"""
    IFS= read -r initialize
    printf '%s\n' '{"id":1,"result":{}}'
    IFS= read -r initialized
    IFS= read -r account
    printf '%s\n' '{"id":2,"result":{"account":{"type":"apiKey"}}}'
    """#)
    defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
    #expect(throws: IntegrationError.self) { try CodexIntegration.read(executable: executable) }
}
