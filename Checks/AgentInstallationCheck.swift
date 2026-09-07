import Foundation

@main enum AgentInstallationCheck {
    static func main() throws {
        let value = try AgentInstallation.probe(executable: "/bin/echo", arguments: ["fixture version 1"])
        precondition(value == "fixture version 1")
        do {
            _ = try AgentInstallation.probe(executable: "/bin/sleep", arguments: ["3"], timeout: 0.05)
            preconditionFailure("Timeout was not enforced")
        } catch {}
        do {
            _ = try AgentInstallation.probe(executable: "/usr/bin/false", arguments: [])
            preconditionFailure("Failure was not reported")
        } catch {}
        print("PASS version output, failed command, bounded timeout")
    }
}
