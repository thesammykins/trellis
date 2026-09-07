import Foundation

/// Codex owns authentication and the visible task. This is not a no-tools model API.
enum CodexModelClient {
    static let nativeGenerationSupported = false
    static let dreamingSupported = false
    static let restrictionReason = "Codex's read-only sandbox does not prevent file reads. Tool and global context isolation have not been verified."
    static let interactiveDisclosure = "Opens a separate Codex task using Codex's configured account. Codex can read files and load its own instructions and integrations. The reviewed prompt appears in local process arguments and may be retained in Codex history."

    /// Pass these directly to the executable, never through a shell command string.
    /// The one-use launcher must not save these arguments in the workspace archive.
    static func interactiveArguments(prompt: String, model: String? = nil) throws -> [String] {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !prompt.utf8.contains(0), prompt.utf8.count <= 8 * 1024 else {
            throw CodexTaskError.invalidPrompt
        }
        var arguments = ["--sandbox", "read-only", "--ask-for-approval", "never"]
        if let model {
            guard !model.isEmpty, model.utf8.count <= 256,
                  !model.hasPrefix("-"), !model.contains(where: { $0.isWhitespace || $0.isNewline }),
                  !model.utf8.contains(0) else { throw CodexTaskError.invalidModel }
            arguments += ["--model", model]
        }
        // End option parsing so a reviewed prompt cannot become a CLI option.
        return arguments + ["--", prompt]
    }
}

enum CodexTaskError: LocalizedError {
    case invalidPrompt
    case invalidModel

    var errorDescription: String? {
        switch self {
        case .invalidPrompt: "Choose nonempty context of at most 8 KiB without null characters."
        case .invalidModel: "Choose a valid Codex model ID."
        }
    }
}
