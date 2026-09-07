import Foundation

enum ShellIntegration {
    /// Returns a per-process environment for Ghostty's bundled automatic shell integration.
    /// The caller owns applying this environment to a newly launched shell.
    static func env(
        for executable: String,
        resourceDirectory: URL,
        inherited: [String: String]
    ) -> [String: String] {
        let shellIntegrationDirectory = resourceDirectory
            .appendingPathComponent("shell-integration", isDirectory: true)
        let fileManager = FileManager.default

        switch URL(fileURLWithPath: executable).lastPathComponent {
        case "zsh":
            let zshDirectory = shellIntegrationDirectory.appendingPathComponent("zsh", isDirectory: true)
            guard fileManager.fileExists(atPath: zshDirectory.appendingPathComponent(".zshenv").path) else {
                return inherited
            }

            var environment = enablingTitle(in: inherited)
            if let originalZdotdir = inherited["ZDOTDIR"] {
                environment["GHOSTTY_ZSH_ZDOTDIR"] = originalZdotdir
            }
            environment["ZDOTDIR"] = zshDirectory.path
            return environment

        case "fish":
            let fishScript = shellIntegrationDirectory
                .appendingPathComponent("fish/vendor_conf.d/ghostty-shell-integration.fish")
            guard fileManager.fileExists(atPath: fishScript.path) else {
                return inherited
            }

            var environment = enablingTitle(in: inherited)
            let integrationPath = shellIntegrationDirectory.path
            environment["GHOSTTY_SHELL_INTEGRATION_XDG_DIR"] = integrationPath
            let xdgDirectories = inherited["XDG_DATA_DIRS"] ?? "/usr/local/share:/usr/share"
            environment["XDG_DATA_DIRS"] = prepend(integrationPath, toPathList: xdgDirectories)
            return environment

        default:
            return inherited
        }
    }

    private static func enablingTitle(in environment: [String: String]) -> [String: String] {
        var environment = environment
        let features = environment["GHOSTTY_SHELL_FEATURES"]?
            .split(separator: ",")
            .map(String.init) ?? []
        if !features.contains("title") {
            environment["GHOSTTY_SHELL_FEATURES"] = (features + ["title"]).joined(separator: ",")
        }
        return environment
    }

    private static func prepend(_ value: String, toPathList pathList: String) -> String {
        let entries = pathList.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard !entries.contains(value) else { return pathList }
        return value + ":" + pathList
    }
}
