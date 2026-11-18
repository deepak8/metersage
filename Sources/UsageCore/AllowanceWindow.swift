import Foundation

/// Stable display order; never add together independent model-group allowances.
public enum AllowanceWindow: String, CaseIterable, Identifiable, Sendable {
    case fiveHour, weekly
    public var id: String { rawValue }
    public var title: String { self == .fiveHour ? "5-hour" : "Weekly" }
}

extension Reading {
    public func quota(for window: AllowanceWindow, at now: Date = .now) -> Quota? {
        quotas.filter {
            $0.label.lowercased().components(separatedBy: " · ").last == window.title.lowercased()
                && ($0.resetsAt.map { $0 > now } ?? true)
        }.min { $0.remaining < $1.remaining }
    }
}
