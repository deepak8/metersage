import Darwin
import Foundation
import UsageCore

/// Ask the authenticated official client for its built-in usage panel. No model
/// prompt, credential access, user workspace, hooks, or MCP servers are involved.
enum ClaudeUsageProbe {
    static let arguments = ["--ax-screen-reader", "--strict-mcp-config", "--tools", "",
        "--settings", #"{"disableAllHooks":true,"remoteControlAtStartup":false,"statusLine":{"type":"command","command":"/usr/bin/true"}}"#]

    static func read(executable: URL) async throws -> Reading {
        let cancellation = BoundedCommand.Cancellation()
        return try await withTaskCancellationHandler {
            try await Task.detached { try readSynchronously(executable: executable, cancellation: cancellation) }.value
        } onCancel: { cancellation.cancel() }
    }

    static func readSynchronously(executable: URL, timeout: TimeInterval = 35,
                                  cancellation: BoundedCommand.Cancellation = .init()) throws -> Reading {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageMonitor-ClaudeProbe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let guardFile = directory.appendingPathComponent("no-browser")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: guardFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: guardFile.path)
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["BROWSER"] = guardFile.path
        environment["DISABLE_AUTOUPDATER"] = "1"
        // A subscription check must not silently use an API key or cloud backend.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"] { environment.removeValue(forKey: key) }
        var master: Int32 = -1, slave: Int32 = -1
        var size = winsize(ws_row: 120, ws_col: 180, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw CommandFailure.launchFailed }
        defer { close(master); close(slave) }
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw CommandFailure.launchFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw CommandFailure.launchFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0 else { throw CommandFailure.launchFailed }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            guard posix_spawn_file_actions_adddup2(&actions, slave, descriptor) == 0 else { throw CommandFailure.launchFailed }
        }
        guard posix_spawn_file_actions_addclose(&actions, master) == 0,
              posix_spawn_file_actions_addclose(&actions, slave) == 0 else { throw CommandFailure.launchFailed }
        var argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        var envp = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for p in argv { free(p) }; for p in envp { free(p) } }
        var pid: pid_t = 0
        guard !cancellation.isCancelled else { throw CommandFailure.cancelled }
        guard posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &envp) == 0 else { throw CommandFailure.launchFailed }
        var status: Int32 = 0, reaped = false
        defer {
            kill(-pid, SIGTERM); if !reaped { kill(pid, SIGTERM) }
            Thread.sleep(forTimeInterval: 0.1)
            kill(-pid, SIGKILL)
            if !reaped {
                kill(pid, SIGKILL)
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            }
        }
        func send(_ value: String) throws {
            let bytes = Array(value.utf8)
            guard bytes.withUnsafeBytes({ Darwin.write(master, $0.baseAddress, $0.count) }) == bytes.count else { throw CommandFailure.unsuccessful }
        }
        let start = ProcessInfo.processInfo.systemUptime
        var capture = Data(), buffer = [UInt8](repeating: 0, count: 16384)
        var trusted = false, sent = false, sentAt = start, lastChange = start
        var previous = ""
        while ProcessInfo.processInfo.systemUptime - start < timeout {
            if cancellation.isCancelled { throw CommandFailure.cancelled }
            let count = Darwin.read(master, &buffer, buffer.count)
            if count > 0 {
                capture.append(contentsOf: buffer.prefix(count))
                guard capture.count <= 1_048_576 else { throw CommandFailure.tooLarge }
            }
            let now = ProcessInfo.processInfo.systemUptime
            let screen = TerminalScreen.render(capture)
            if screen != previous { previous = screen; lastChange = now }
            if !trusted, screen.contains(directory.lastPathComponent), screen.contains("Yes, I trust this folder"), screen.contains("Enter y/n") {
                try send("y\r"); trusted = true
            }
            if !sent, screen.contains("Claude Code v"), screen.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces) == "$" }) {
                try send("/usage"); Thread.sleep(forTimeInterval: 0.15); try send("\r")
                sent = true; sentAt = now
            }
            if sent, now - sentAt >= 2, now - lastChange >= 0.8 {
                do { return try ClaudeUsageReport.parse(screen) }
                catch ClaudeUsageError.loading {} // Wait for the refreshed panel.
                catch ClaudeUsageError.unavailable {} // Startup or intermediate frame.
            }
            if !sent, now - lastChange > 2, screen.lowercased().contains("sign in") { throw ClaudeUsageError.authenticationRequired }
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { reaped = true; throw ClaudeUsageError.unavailable }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw CommandFailure.timedOut
    }
}
