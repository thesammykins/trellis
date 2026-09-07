import Foundation
@main struct TerminalLocationCheck {
    static func main() {
        let launch = URL(fileURLWithPath: "/tmp/project")
        let local = TerminalLocation(reportedPath: "/tmp/project/sub", launchDirectory: launch, remoteHost: nil, running: true)
        precondition(local.localURL?.path == "/tmp/project/sub" && local.label == "Current folder")
        let restarted = TerminalLocation(reportedPath: "/tmp/old", launchDirectory: launch, remoteHost: nil, running: false)
        precondition(restarted.localURL == launch && restarted.label == "Started in")
        let remote = TerminalLocation(reportedPath: "/tmp/project", launchDirectory: launch, remoteHost: "fixture", running: true)
        precondition(remote.localURL == nil && remote.unavailableReason != nil)
        for invalid in ["relative", "file:///tmp/a", "/tmp/a\n", "/tmp/\0", String(repeating: "/", count: 4097)] {
            precondition(TerminalLocation.validatedPath(invalid) == nil)
            precondition(TerminalLocation(reportedPath: invalid, launchDirectory: launch, remoteHost: nil, running: true).localURL == nil)
        }
        precondition(TerminalLocation.validatedPath("/tmp/空 間") != nil)
        print("Terminal location checks passed")
    }
}
