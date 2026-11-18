import Foundation

public enum AntigravityReportError: LocalizedError {
    case invalidReport, noMeasuredQuota
    public var errorDescription: String? {
        switch self {
        case .invalidReport: "Antigravity did not return a successful usage report. Open the official CLI to check sign-in, then try again."
        case .noMeasuredQuota: "Antigravity returned no measured allowance for this account. Check /usage in the official CLI."
        }
    }
}

public enum AntigravityReport {
    public static func supportsUsageReport(version: String) -> Bool {
        guard let match = version.range(of: #"\b\d+\.\d+\.\d+\b"#, options: .regularExpression) else { return false }
        let parts = version[match].split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 && !parts.lexicographicallyPrecedes([1, 1, 11])
    }

    public static func parse(_ data: Data, now: Date = .now) throws -> Reading {
        let report: Envelope
        do { report = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw AntigravityReportError.invalidReport }
        guard report.status == "SUCCESS", report.command?.name == "usage",
              (report.num_turns ?? 0) == 0, let groups = report.command?.data?.groups else {
            throw AntigravityReportError.invalidReport
        }
        var quotas: [Quota] = []
        var unavailable: [String] = []
        var seen: Set<String> = []
        for group in groups {
            for bucket in group.buckets ?? [] {
                guard bucket.disabled != true, let id = bucket.id, !id.isEmpty, seen.insert(id).inserted else { continue }
                let window = switch bucket.window {
                case "weekly": "Weekly"
                case "5h": "5-hour"
                default: bucket.name ?? id
                }
                let label = (group.name ?? "Model group") + " · " + window
                guard let fraction = bucket.remaining_fraction, fraction.isFinite, (0...1).contains(fraction) else {
                    unavailable.append(label)
                    continue
                }
                let reset = bucket.reset_time.flatMap(parseReset)
                    ?? bucket.reset_in_seconds.flatMap { $0.isFinite && $0 > 0 ? now.addingTimeInterval($0) : nil }
                quotas.append(Quota(label: label, usedPercent: (1 - fraction) * 100, resetsAt: reset, bucketID: id))
            }
        }
        guard !quotas.isEmpty else { throw AntigravityReportError.noMeasuredQuota }
        // The envelope's usage counter belongs to this read-only command, not
        // account activity. Do not show its zeros as daily tokens or spending.
        return Reading(provider: .antigravity, quotas: quotas, unavailableQuotas: unavailable,
                       observedAt: now, scope: "Account quota groups · official Antigravity CLI")
    }

    private static func parseReset(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    private struct Envelope: Decodable {
        var status: String?
        var num_turns: Int?
        var command: Command?
    }
    private struct Command: Decodable { var name: String?; var data: ReportData? }
    private struct ReportData: Decodable { var groups: [Group]? }
    private struct Group: Decodable { var name: String?; var buckets: [Bucket]? }
    private struct Bucket: Decodable {
        var id: String?
        var name: String?
        var window: String?
        var disabled: Bool?
        var remaining_fraction: Double?
        var reset_time: String?
        var reset_in_seconds: Double?
    }
}
