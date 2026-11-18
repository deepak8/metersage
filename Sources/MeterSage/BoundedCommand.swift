import Darwin
import Foundation

enum CommandFailure: LocalizedError, Equatable {
    case timedOut, cancelled, tooLarge, launchFailed, unsuccessful
    var errorDescription: String? {
        switch self {
        case .timedOut: "The official CLI timed out. Check its sign-in in Terminal, then try again."
        case .cancelled: "The usage check was cancelled."
        case .tooLarge: "The CLI returned an unexpectedly large report."
        case .launchFailed: "Could not start the official CLI. Check its installation."
        case .unsuccessful: "The CLI could not complete the usage check. Check its sign-in in Terminal, then try again."
        }
    }
}

/// Own a separate process group so deadlines/cancellation clean up only this
/// command and its children. File-backed stdout avoids pipe/descendant deadlocks.
enum BoundedCommand {
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    static func run(executable: URL, arguments: [String], environment: [String: String], directory: URL,
                    timeout: TimeInterval = 45, maxBytes: Int = 1_048_576, cancellation: Cancellation) throws -> Data {
        let output = directory.appendingPathComponent(UUID().uuidString + ".stdout")
        defer { try? FileManager.default.removeItem(at: output) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw CommandFailure.launchFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw CommandFailure.launchFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, output.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0 else {
            throw CommandFailure.launchFailed
        }
        let strings = [executable.path] + arguments
        let envStrings = environment.map { $0.key + "=" + $0.value }
        var argv = strings.map { strdup($0) } + [nil]
        var envp = envStrings.map { strdup($0) } + [nil]
        defer { for p in argv { free(p) }; for p in envp { free(p) } }
        var pid: pid_t = 0
        guard !cancellation.isCancelled else { throw CommandFailure.cancelled }
        guard posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &envp) == 0 else {
            throw CommandFailure.launchFailed
        }
        var reaped = false
        var status: Int32 = 0
        defer {
            // Even a successful report may have started background helpers.
            kill(-pid, SIGTERM)
            if !reaped { Thread.sleep(forTimeInterval: 0.1) }
            kill(-pid, SIGKILL)
            if !reaped {
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            if cancellation.isCancelled { throw CommandFailure.cancelled }
            if ProcessInfo.processInfo.systemUptime >= deadline { throw CommandFailure.timedOut }
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > maxBytes { throw CommandFailure.tooLarge }
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { reaped = true; break }
            if result == -1 && errno != EINTR { throw CommandFailure.unsuccessful }
            Thread.sleep(forTimeInterval: 0.025)
        }
        // Stop any inherited stdout writers before the final size check/read.
        kill(-pid, SIGKILL)
        guard status == 0 else { throw CommandFailure.unsuccessful }
        let size = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else { throw CommandFailure.tooLarge }
        return try Data(contentsOf: output)
    }
}
