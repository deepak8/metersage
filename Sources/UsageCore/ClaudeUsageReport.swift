import Foundation

public enum ClaudeUsageError: LocalizedError {
    case loading, unavailable, authenticationRequired, rateLimited, cachedAgeUnknown, setupRequired
    case rateLimitedUntil(Date)
    public var errorDescription: String? {
        switch self {
        case .loading: "Claude’s usage panel is still loading. Try Refresh again shortly."
        case .unavailable: "Claude did not return a recognizable subscription usage panel."
        case .authenticationRequired: "Sign in through the official Claude Code CLI, then check the connection."
        case .rateLimited: "Claude’s usage endpoint is rate limited. Keeping the last reading; automatic checks will back off."
        case .rateLimitedUntil(let date): "Claude’s usage endpoint is rate limited until \(date.formatted(date: .omitted, time: .shortened)). This affects usage reporting, not your permission to chat."
        case .cachedAgeUnknown: "Claude returned cached usage without a readable capture age. Keeping the previous reading."
        case .setupRequired: "Complete Claude Code’s initial setup in Terminal, then retry."
        }
    }
}

public enum ClaudeUsageReport {
    public static func parse(_ text: String, now: Date = .now, timeZone: TimeZone = .current) throws -> Reading {
        let lower = text.lowercased()
        let rateLimited = lower.contains("rate limited") || lower.contains("usage endpoint is rate") || matches(#"\b429\b"#, lower)
        let retryAt = retryAfter(in: text, now: now, timeZone: timeZone)
        if lower.contains("showing last-known usage") == false,
           rateLimited {
            if let retryAt { throw ClaudeUsageError.rateLimitedUntil(retryAt) }
            throw ClaudeUsageError.rateLimited
        }
        if lower.contains("sign in to") || lower.contains("not logged in") || lower.contains("please log in") { throw ClaudeUsageError.authenticationRequired }
        if lower.contains("refreshing…") || lower.contains("refreshing...") || lower.contains("loading usage") { throw ClaudeUsageError.loading }
        var observed = now
        let cached = lower.contains("showing last-known usage")
        if cached {
            guard let marker = lower.range(of: "showing last-known usage") else { throw ClaudeUsageError.cachedAgeUnknown }
            let notice = String(lower[marker.lowerBound...].prefix(400))
            guard let age = first(#"((?:\d+(?:\.\d+)?\s*(?:seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)\s*)+)ago"#, notice),
                  let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)"#) else { throw ClaudeUsageError.cachedAgeUnknown }
            let value = age[1]
            var seconds: Double = 0
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
                guard let nr = Range(match.range(at: 1), in: value), let ur = Range(match.range(at: 2), in: value), let n = Double(value[nr]) else { continue }
                let unit = value[ur]
                seconds += n * (unit.hasPrefix("h") ? 3600 : (unit.hasPrefix("m") ? 60 : 1))
            }
            observed = now.addingTimeInterval(-seconds)
        }
        let lines = text.components(separatedBy: .newlines)
        var quotas: [Quota] = []
        var indices: [(Int, String)] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if matches(#"(?i)^Current\s+(session|week(?:\s*\([^\)]*\))?)\s*$"#, trimmed) {
                indices.append((index, trimmed))
            }
        }
        for (offset, item) in indices.enumerated() {
            let end = offset + 1 < indices.count ? indices[offset + 1].0 : lines.count
            let section = lines[(item.0 + 1)..<end].prefix(12)
                .prefix { !$0.lowercased().contains("what's contributing") && !$0.lowercased().contains("what’s contributing") && !$0.lowercased().contains("usage credits") }
            let body = section.joined(separator: "\n")
            guard let match = first(#"(?i)(\d+(?:\.\d+)?)\s*%\s*(used|left|remaining)"#, body),
                  let amount = Double(match[1]), (0...100).contains(amount) else { continue }
            let used = match[2].lowercased() == "used" ? amount : 100 - amount
            let title = item.1
            let id: String
            let label: String
            if title.lowercased().contains("session") { id = "claude-5h"; label = "5-hour" }
            else if title.lowercased() == "current week" || title.lowercased().contains("all models") { id = "claude-weekly"; label = "Weekly" }
            else {
                let model = first(#"\(([^\)]+)\)"#, title)?[1] ?? "Model"
                id = "claude-weekly-" + model.lowercased().replacingOccurrences(of: " ", with: "-")
                label = model + " · Weekly"
            }
            let resetLine = section.first { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("reset") }?.trimmingCharacters(in: .whitespaces)
            let quota = Quota(label: label, usedPercent: used,
                              resetsAt: resetLine.flatMap { parseReset($0, now: observed, timeZone: timeZone) },
                              bucketID: id, resetDescription: resetLine)
            if let previous = quotas.firstIndex(where: { $0.bucketID == id }) { quotas[previous] = quota }
            else { quotas.append(quota) }
        }
        guard !quotas.isEmpty else { throw ClaudeUsageError.unavailable }
        var reading = Reading(provider: .claude, quotas: quotas, observedAt: observed,
                              quotaIsCached: cached, scope: "Account allowance · official Claude Code /usage")
        reading.quotaRetryAfter = retryAt ?? (rateLimited ? now.addingTimeInterval(900) : nil)
        return reading
    }

    public static func retryAfter(in text: String, now: Date, timeZone: TimeZone) -> Date? {
        guard let match = first(#"(?i)rate\s+limited\s+until\s+(\d{1,2}:\d{2}\s*(?:am|pm)?|\d{1,2}\s*(?:am|pm))(?:\s*(\([^\)]+\)))?"#, text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: match[2].trimmingCharacters(in: CharacterSet(charactersIn: "()"))) ?? timeZone
        let raw = match[1].replacingOccurrences(of: " ", with: "").lowercased()
        let numbers = raw.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").split(separator: ":")
        guard let hour = Int(numbers[0]), hour < 24 else { return nil }
        let minute = numbers.count > 1 ? Int(numbers[1]) ?? -1 : 0
        guard (0...59).contains(minute) else { return nil }
        if raw.hasSuffix("am") || raw.hasSuffix("pm"), !(1...12).contains(hour) { return nil }
        let adjusted = raw.hasSuffix("pm") ? hour % 12 + 12 : (raw.hasSuffix("am") ? hour % 12 : hour)
        return calendar.nextDate(after: now, matching: DateComponents(hour: adjusted, minute: minute, second: 0), matchingPolicy: .nextTime)
    }

    public static func parseReset(_ text: String, now: Date, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        var zone = timeZone
        if let name = first(#"\(([^\)]+)\)"#, text)?[1], let parsed = TimeZone(identifier: name) { zone = parsed }
        calendar.timeZone = zone
        let lower = text.lowercased()
        if let relative = first(#"resets?\s+in\s+(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d)"#, lower), let value = Double(relative[1]) {
            let unit = relative[2]
            return now.addingTimeInterval(value * (unit.hasPrefix("d") ? 86400 : (unit.hasPrefix("h") ? 3600 : 60)))
        }
        var raw = text.replacingOccurrences(of: #"(?i)^resets?\s+"#, with: "", options: .regularExpression)
        raw = raw.replacingOccurrences(of: #"\s*\([^\)]+\)\s*$"#, with: "", options: .regularExpression)
        raw = raw.replacingOccurrences(of: #"(?i)\s+at\s+"#, with: " ", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone
        formatter.defaultDate = now
        for format in ["MMM d yyyy h:mma", "MMM d, yyyy h:mma", "MMM d h:mma", "MMM d ha", "EEE h:mma", "h:mma", "ha", "H:mm"] {
            formatter.dateFormat = format
            if var date = formatter.date(from: raw) {
                // defaultDate fills omitted seconds too; displayed reset times
                // have minute precision and must not drift with each fetch.
                date = calendar.dateInterval(of: .minute, for: date)?.start ?? date
                if date <= now {
                    let unit: Calendar.Component = format.hasPrefix("MMM") ? .year : (format.hasPrefix("EEE") ? .weekOfYear : .day)
                    let horizon: TimeInterval = format.hasPrefix("MMM") || format.hasPrefix("EEE") ? 8 * 86400 : 6 * 3600
                    if let advanced = calendar.date(byAdding: unit, value: 1, to: date), advanced.timeIntervalSince(now) <= horizon { date = advanced }
                }
                return date
            }
        }
        return nil
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool { first(pattern, text) != nil }
    private static func first(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}
