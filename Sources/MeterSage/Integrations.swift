import AppKit
import CryptoKit
import Foundation
import UsageCore

enum LocalFiles {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UsageMonitor", isDirectory: true)
    }
    static var bridge: URL { root.appendingPathComponent("claude", isDirectory: true) }
    static func receiveStatusline() throws {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let snapshot = try ClaudeSnapshot.parse(input)
        try FileManager.default.createDirectory(at: bridge, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = SHA256.hash(data: Data(snapshot.sessionID.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = bridge.appendingPathComponent(key + ".json")
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        // Output is intentionally short; users may chain their existing status line.
        print("MeterSage connected")
    }
    static func latestClaude() -> Reading? {
        let files = (try? FileManager.default.contentsOfDirectory(at: bridge, includingPropertiesForKeys: nil)) ?? []
        let latest = files.filter { $0.pathExtension == "json" }.compactMap { url -> ClaudeSnapshot? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(ClaudeSnapshot.self, from: data)
        }.max { $0.observedAt < $1.observedAt }
        guard let latest else { return nil }
        return Reading(provider: .claude, quotas: latest.quotas, tokens: latest.tokens,
                       estimatedCost: latest.cost, observedAt: latest.observedAt, metricsObservedAt: latest.observedAt,
                       scope: "Latest CLI session · context tokens / session cost")
    }
    static func executable(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static func cliName(for provider: Provider) -> String {
        switch provider { case .codex: "codex"; case .claude: "claude"; case .antigravity: "agy" }
    }
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    @MainActor static func openLogin(_ provider: Provider) -> Bool {
        let name = cliName(for: provider)
        guard let executable = executable(name) else { return false }
        let arguments = switch provider {
        case .codex: " login"
        case .claude: " auth login"
        case .antigravity: ""
        }
        let command = shellQuote(executable.path) + arguments
        let script = root.appendingPathComponent("login-\(name).command")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(("#!/bin/zsh\n" + command + "\n").utf8).write(to: script, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            return NSWorkspace.shared.open(script)
        } catch { return false }
    }
}

struct CodexResult: Sendable {
    var reading: Reading
    var days: [UsageDay]
    var historyState: DailyHistoryState
}

private enum CodexDailyError: Error { case unsupported }

enum IntegrationError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case let .unavailable(message) = self { message } else { nil } }
}

enum CodexIntegration {
    static func read(executable: URL) throws -> CodexResult {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Closing stdin on timeout asks the server to finish and unblocks the reader.
        let timeout = DispatchWorkItem {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func response(_ id: Int) throws -> [String: Any] {
            while true {
                var line = Data()
                while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
                    if byte[0] == 10 { break }
                    line.append(byte)
                    if line.count > 4_000_000 { throw IntegrationError.unavailable("Codex returned an oversized response.") }
                }
                guard !line.isEmpty else { throw IntegrationError.unavailable("Codex did not respond. Check CLI sign-in and try again.") }
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any], message["id"] as? Int == id else { continue }
                if let error = message["error"] as? [String: Any] {
                    if id == 4, error["code"] as? Int == -32601 { throw CodexDailyError.unsupported }
                    throw IntegrationError.unavailable("This Codex CLI could not provide the requested usage. Check sign-in or update the CLI.")
                }
                return message["result"] as? [String: Any] ?? [:]
            }
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "metersage", "version": "0.1.0"]]])
        _ = try response(1)
        try send(["method": "initialized"])
        try send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
        let accountResponse = try response(2)
        guard let account = accountResponse["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
            throw IntegrationError.unavailable("Sign in to Codex with your ChatGPT account to read subscription allowances.")
        }
        try send(["id": 3, "method": "account/rateLimits/read"])
        let limits = try response(3)
        let all = limits["rateLimitsByLimitId"] as? [String: [String: Any]]
        let buckets: [(String, [String: Any])] = if let all, !all.isEmpty {
            all.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let single = limits["rateLimits"] as? [String: Any] {
            [("codex", single)]
        } else { [] }
        let quotas = buckets.flatMap { key, bucket in
            ["primary", "secondary"].compactMap { window -> Quota? in
                guard let data = bucket[window] as? [String: Any], let used = data["usedPercent"] as? Double else { return nil }
                let minutes = data["windowDurationMins"] as? Int
                let period = minutes.map { $0 == 10080 ? "Weekly" : ($0 % 60 == 0 ? "\($0 / 60)-hour" : "\($0)-minute") } ?? window.capitalized
                return Quota(label: buckets.count > 1 ? "\(key) · \(period)" : period, usedPercent: used,
                             resetsAt: (data["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) })
            }
        }
        var days: [UsageDay] = []
        var historyState = DailyHistoryState.notReported
        do {
          try send(["id": 4, "method": "account/usage/read"])
          let usage = try response(4)
          if let daily = usage["dailyUsageBuckets"] as? [[String: Any]] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
            days = daily.compactMap { item in
                guard let rawDate = item["startDate"] as? String, let date = formatter.date(from: rawDate), let tokens = item["tokens"] as? Int else { return nil }
                return UsageDay(date: date, provider: .codex, tokens: tokens)
            }
            historyState = daily.isEmpty ? .noRecords : (days.count == daily.count ? .reported : .failed)
          }
        } catch CodexDailyError.unsupported {
            historyState = .unsupported
        } catch {
            historyState = .failed
        }
        let today = days.first { Calendar.current.isDateInToday($0.date) }?.tokens
        return CodexResult(reading: Reading(provider: .codex, account: account["email"] as? String,
                                           plan: (account["planType"] as? String)?.capitalized,
                                           quotas: quotas, tokens: today, scope: "Account allowance · provider daily tokens"), days: days, historyState: historyState)
    }
}
