import Foundation
import UsageCore

enum AntigravityIntegration {
    static func read(executable: URL) async throws -> Reading {
        let cancellation = BoundedCommand.Cancellation()
        return try await withTaskCancellationHandler {
            try await Task.detached { try readSynchronously(executable: executable, cancellation: cancellation) }.value
        } onCancel: { cancellation.cancel() }
    }

    static func readSynchronously(executable: URL, cancellation: BoundedCommand.Cancellation = .init()) throws -> Reading {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageMonitor-agy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        // Passive refreshes must never open login windows. Explicit sign-in
        // still launches the unmodified official CLI from the connection sheet.
        let guardDirectory = directory.appendingPathComponent("launchers")
        try FileManager.default.createDirectory(at: guardDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for name in ["open", "xdg-open", "sensible-browser"] {
            let file = guardDirectory.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 1\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
        environment["PATH"] = guardDirectory.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["BROWSER"] = guardDirectory.appendingPathComponent("open").path
        let versionData = try BoundedCommand.run(executable: executable, arguments: ["--version"], environment: environment,
                                                directory: directory, timeout: 8, maxBytes: 16_384, cancellation: cancellation)
        guard AntigravityReport.supportsUsageReport(version: String(decoding: versionData, as: UTF8.self)) else {
            throw IntegrationError.unavailable("Update Antigravity CLI to version 1.1.11 or later before connecting.")
        }
        let data = try BoundedCommand.run(executable: executable,
                                         arguments: ["-p", "/usage", "--output-format", "json", "--disable-slash-commands=false", "--print-timeout", "40s"],
                                         environment: environment, directory: directory, cancellation: cancellation)
        return try AntigravityReport.parse(data)
    }
}
