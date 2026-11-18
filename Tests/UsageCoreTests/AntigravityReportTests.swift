import Foundation
import Testing
@testable import UsageCore

private func report(_ groups: String, status: String = "SUCCESS", command: String = "usage", turns: Int = 0) -> Data {
    Data("""
    {"status":"\(status)","num_turns":\(turns),"usage":{"total_tokens":0},"command":{"name":"\(command)","data":{"groups":\(groups)}}}
    """.utf8)
}

@Test func antigravityPreservesSeparateQuotaGroupsAndDoesNotInventActivity() throws {
    let data = report(#"""
    [
      {"name":"Gemini Models","buckets":[
        {"id":"gemini-weekly","window":"weekly","remaining_fraction":0.8,"reset_time":"2030-01-20T10:30:00Z"},
        {"id":"gemini-5h","window":"5h","remaining_fraction":0,"reset_time":"2030-01-19T10:30:00.500Z"}]},
      {"name":"Claude and GPT models","buckets":[
        {"id":"3p-weekly","window":"weekly","remaining_fraction":0.65},
        {"id":"3p-5h","window":"5h","remaining_fraction":1}]},
      {"name":"Additional model","buckets":[{"id":"special-weekly","window":"weekly","remaining_fraction":0.4}]}
    ]
    """#)
    let reading = try AntigravityReport.parse(data)
    #expect(reading.quotas.count == 5)
    #expect(reading.quotas[1].remaining == 0)
    #expect(reading.quotas[1].resetsAt != nil)
    #expect(reading.quotas[2].label == "Claude and GPT models · Weekly")
    #expect(reading.quotas[4].bucketID == "special-weekly")
    #expect(reading.tokens == nil)
    #expect(reading.estimatedCost == nil)
    #expect(reading.account == nil)
}

@Test func antigravitySkipsDisabledBucketsKeepsUnknownsAndDeduplicatesSharedLimits() throws {
    let reading = try AntigravityReport.parse(report(#"""
    [{"name":"Gemini","buckets":[
      {"id":"weekly","window":"weekly","remaining_fraction":0.9},
      {"id":"weekly","window":"weekly","remaining_fraction":0.9},
      {"id":"5h","window":"5h","remaining_amount":200},
      {"id":"invalid","remaining_fraction":1.5},
      {"id":"disabled","remaining_fraction":0,"disabled":true}]}]
    """#))
    #expect(reading.quotas.count == 1)
    #expect(reading.unavailableQuotas?.count == 2)
}

@Test(arguments: ["ERROR", "PENDING", "success"])
func antigravityRejectsUnsuccessfulReports(_ status: String) {
    #expect(throws: AntigravityReportError.self) {
        try AntigravityReport.parse(report("[]", status: status))
    }
}

@Test func antigravityRejectsModelTurnsWrongCommandsAndUnmeasuredAvailability() {
    #expect(throws: AntigravityReportError.self) { try AntigravityReport.parse(report("[]", command: "model")) }
    #expect(throws: AntigravityReportError.self) { try AntigravityReport.parse(report("[]", turns: 1)) }
    #expect(throws: AntigravityReportError.self) {
        try AntigravityReport.parse(report(#"[{"name":"Gemini","buckets":[{"id":"weekly","reset_time":"2030-01-20T00:00:00Z"}]}]"#))
    }
    #expect(throws: AntigravityReportError.self) { try AntigravityReport.parse(Data("not JSON".utf8)) }
}

@Test func antigravityVersionGatePreventsOldCliPromptFallback() {
    #expect(!AntigravityReport.supportsUsageReport(version: "1.1.10"))
    #expect(!AntigravityReport.supportsUsageReport(version: "unknown"))
    #expect(AntigravityReport.supportsUsageReport(version: "agy 1.1.11"))
    #expect(AntigravityReport.supportsUsageReport(version: "1.5.10"))
    #expect(AntigravityReport.supportsUsageReport(version: "2.0.0"))
}
