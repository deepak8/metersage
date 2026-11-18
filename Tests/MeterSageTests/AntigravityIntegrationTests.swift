import Foundation
import Testing
@testable import MeterSage

private func commandFixture(_ source: String) throws -> (directory: URL, executable: URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UsageMonitor-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let executable = directory.appendingPathComponent("agy")
    try Data(("#!/bin/sh\n" + source).utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return (directory, executable)
}

@Test func antigravityAdapterUsesReadOnlyFlagsAndBlocksBrowserLaunch() throws {
    let fixture = try commandFixture(#"""
    if [ "$1" = "--version" ]; then printf '1.5.10\n'; exit 0; fi
    [ "$AGY_CLI_DISABLE_AUTO_UPDATE" = 'true' ] || exit 1
    [ "$1" = '-p' ] && [ "$2" = '/usage' ] && [ "$3" = '--output-format' ] && [ "$4" = 'json' ] || exit 1
    [ "$5" = '--disable-slash-commands=false' ] || exit 1
    if "$BROWSER" 'https://example.invalid'; then exit 1; fi
    printf '%s\n' '{"status":"SUCCESS","num_turns":0,"command":{"name":"usage","data":{"groups":[{"name":"Gemini","buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5}]}]}}}'
    """#)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let reading = try AntigravityIntegration.readSynchronously(executable: fixture.executable)
    #expect(reading.provider.rawValue == "antigravity")
    #expect(reading.quotas.first?.remaining == 50)
}

@Test func antigravityAdapterDoesNotRunUsageOnAnOldCli() throws {
    let fixture = try commandFixture(#"""
    if [ "$1" = '--version' ]; then printf '1.1.10\n'; exit 0; fi
    touch 'UNEXPECTED-USAGE'
    exit 1
    """#)
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    #expect(throws: IntegrationError.self) { try AntigravityIntegration.readSynchronously(executable: fixture.executable) }
}

@Test func cliCommandEnforcesDeadlineOutputBoundAndCancellation() throws {
    let sleeper = try commandFixture("sleep 30\n")
    defer { try? FileManager.default.removeItem(at: sleeper.directory) }
    #expect(throws: CommandFailure.timedOut) {
        try BoundedCommand.run(executable: sleeper.executable, arguments: [], environment: ["PATH":"/usr/bin:/bin"],
                               directory: sleeper.directory, timeout: 0.15, cancellation: .init())
    }
    let cancellation = BoundedCommand.Cancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancellation.cancel() }
    #expect(throws: CommandFailure.cancelled) {
        try BoundedCommand.run(executable: sleeper.executable, arguments: [], environment: ["PATH":"/usr/bin:/bin"],
                               directory: sleeper.directory, timeout: 3, cancellation: cancellation)
    }
    let large = try commandFixture("printf '%0200d' 0\n")
    defer { try? FileManager.default.removeItem(at: large.directory) }
    #expect(throws: CommandFailure.tooLarge) {
        try BoundedCommand.run(executable: large.executable, arguments: [], environment: [:], directory: large.directory,
                               maxBytes: 64, cancellation: .init())
    }
}
