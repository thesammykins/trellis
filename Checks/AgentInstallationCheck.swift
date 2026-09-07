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
        do {
            _ = try AgentInstallation.probe(executable: "/bin/sh", arguments: ["-c", "printf '%s\\n' 'fixture: Host key verification failed.' >&2; exit 73"])
            preconditionFailure("Failure was not reported")
        } catch {
            precondition(error.localizedDescription.contains("exit 73"))
            precondition(error.localizedDescription.contains("Host key verification failed."), error.localizedDescription)
        }
        do {
            _ = try AgentInstallation.probe(executable: "/bin/sh", arguments: ["-c", "printf '%s' \"$1\" >&2; exit 1", "fixture", String(repeating: "x", count: 2_048)], outputLimit: 65_536)
            preconditionFailure("Failure was not reported")
        } catch {
            precondition(error.localizedDescription.contains(String(repeating: "x", count: 512)))
            precondition(!error.localizedDescription.contains(String(repeating: "x", count: 513)), "Failure output was not bounded")
        }
        let accepted = try AgentInstallation.probe(executable: "/bin/sh", arguments: ["-c", "printf 'login required'; exit 1"], acceptedExitStatuses: [0, 1])
        precondition(accepted == "login required")
        print("PASS version output, bounded failure diagnostics, accepted nonzero status and timeout")
    }
}
