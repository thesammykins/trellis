import Foundation

@main
enum CodexModelCheck {
    static func main() throws {
        let prompt = "--dangerously-bypass-approvals-and-sandbox\n$(touch /tmp/never-run) ' 東京"
        let arguments = try CodexModelClient.interactiveArguments(prompt: prompt)
        assert(arguments == ["--sandbox", "read-only", "--ask-for-approval", "never", "--", prompt])
        let modeled = try CodexModelClient.interactiveArguments(prompt: "Explain", model: "example-model")
        assert(modeled == ["--sandbox", "read-only", "--ask-for-approval", "never", "--model", "example-model", "--", "Explain"])
        for invalid in ["", " \n", "a\0b", String(repeating: "é", count: 4_097)] {
            assertThrows { try CodexModelClient.interactiveArguments(prompt: invalid) }
        }
        for invalid in ["", "--search", "a b", "a\0b", String(repeating: "m", count: 257)] {
            assertThrows { try CodexModelClient.interactiveArguments(prompt: "Explain", model: invalid) }
        }
        assert(!CodexModelClient.nativeGenerationSupported && !CodexModelClient.dreamingSupported)
        assert(CodexModelClient.interactiveDisclosure.contains("process arguments"))
        print("PASS Codex interactive argument boundaries, input bounds, and unavailable native/dreaming capabilities")
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do { _ = try operation(); preconditionFailure("Expected validation failure") } catch {}
    }
}
