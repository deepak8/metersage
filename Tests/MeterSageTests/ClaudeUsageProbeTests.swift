import Darwin
import Foundation
import Testing
@testable import MeterSage

private func claudeFixture(_ source: String) throws -> (URL, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageMonitor-claude-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let file = directory.appendingPathComponent("claude")
    try Data(("#!/bin/sh\n" + source).utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    return (directory, file)
}

@Test func claudeProbeUsesIsolatedPtyAndOnlyBuiltInUsageCommand() throws {
    let fixture = try claudeFixture(#"""
    [ -t 0 ] && [ -t 1 ] || exit 1
    [ "$1" = '--ax-screen-reader' ] && [ "$2" = '--strict-mcp-config' ] || exit 1
    [ "$3" = '--tools' ] && [ -z "$4" ] && [ "$5" = '--settings' ] || exit 1
    case "$6" in *'"disableAllHooks":true'*'"remoteControlAtStartup":false'*'"command":"/usr/bin/true"'*) ;; *) exit 1 ;; esac
    case "$PWD" in *UsageMonitor-ClaudeProbe-*) ;; *) exit 1 ;; esac
    if "$BROWSER" 'https://example.invalid'; then exit 1; fi
    printf 'Permission Required: %s\nYes, I trust this folder\nEnter y/n:\n' "$PWD"
    IFS= read -r answer
    [ "$answer" = 'y' ] || exit 1
    printf 'Claude Code v99.0.0\n$\n'
    IFS= read -r command
    [ "$command" = '/usage' ] || exit 1
    printf 'Current session\n21%% used\nCurrent week (all models)\n16%% used\n'
    sleep 30
    """#)
    defer { try? FileManager.default.removeItem(at: fixture.0) }
    let reading = try ClaudeUsageProbe.readSynchronously(executable: fixture.1, timeout: 8)
    #expect(reading.quotas.map(\.remaining) == [79, 84])
}

@Test func claudePtyDeadlineCancellationAndCleanupAreBounded() throws {
    let fixture = try claudeFixture("echo $$ > \"$0.pid\"\nsleep 30\n")
    defer { try? FileManager.default.removeItem(at: fixture.0) }
    let start = Date()
    #expect(throws: CommandFailure.timedOut) { try ClaudeUsageProbe.readSynchronously(executable: fixture.1, timeout: 1.5) }
    // On a busy Mac the deadline can expire before the shell executes its first
    // line. Assert reaping whenever that line actually ran, without requiring it
    // to run before the deadline being tested.
    let marker = fixture.1.path + ".pid"
    if let value = try? String(contentsOfFile: marker, encoding: .utf8), let pid = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }
    try? FileManager.default.removeItem(atPath: marker)
    let cancellation = BoundedCommand.Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { cancellation.cancel() }
    #expect(throws: CommandFailure.cancelled) { try ClaudeUsageProbe.readSynchronously(executable: fixture.1, timeout: 3, cancellation: cancellation) }
    if let value = try? String(contentsOfFile: marker, encoding: .utf8), let pid = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }
    #expect(Date().timeIntervalSince(start) < 6)
}
