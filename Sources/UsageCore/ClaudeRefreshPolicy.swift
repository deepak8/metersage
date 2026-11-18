import Foundation

/// Provider polling is independent of the faster UI/other-provider interval.
/// A cache fallback delays automatic checks, not an explicit manual retry.
public struct ClaudeRefreshPolicy: Sendable {
    public private(set) var lastAttempt: Date?
    public private(set) var nextAutomaticCheck = Date.distantPast
    public private(set) var rateLimitedUntil: Date?
    public init() {}

    public func deferredUntil(manual: Bool, now: Date) -> Date? {
        if let rateLimitedUntil, rateLimitedUntil > now { return rateLimitedUntil }
        if manual {
            // Debounce repeated clicks without disguising a skipped request as
            // a successful refresh or hammering the upstream usage endpoint.
            if let lastAttempt, lastAttempt.addingTimeInterval(30) > now { return lastAttempt.addingTimeInterval(30) }
        } else if nextAutomaticCheck > now { return nextAutomaticCheck }
        return nil
    }
    public mutating func begin(at now: Date) {
        lastAttempt = now
        nextAutomaticCheck = now.addingTimeInterval(300)
    }
    public mutating func received(_ reading: Reading, at now: Date) {
        nextAutomaticCheck = now.addingTimeInterval(300)
        rateLimitedUntil = reading.quotaRetryAfter.flatMap { $0 > now ? $0 : nil }
    }
    public mutating func failed(_ error: Error, at now: Date) {
        nextAutomaticCheck = now.addingTimeInterval(300)
        if let error = error as? ClaudeUsageError {
            switch error {
            case .rateLimitedUntil(let date): rateLimitedUntil = date; nextAutomaticCheck = date
            case .rateLimited:
                let deadline = now.addingTimeInterval(900)
                rateLimitedUntil = deadline; nextAutomaticCheck = deadline
            default: break
            }
        }
    }
}
