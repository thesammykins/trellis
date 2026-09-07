import Foundation

@main
struct ShellIntegrationCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trellis-shell-integration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let zshDirectory = root.appendingPathComponent("shell-integration/zsh", isDirectory: true)
        let fishDirectory = root.appendingPathComponent("shell-integration/fish/vendor_conf.d", isDirectory: true)
        try FileManager.default.createDirectory(at: zshDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fishDirectory, withIntermediateDirectories: true)
        try Data().write(to: zshDirectory.appendingPathComponent(".zshenv"))
        try Data().write(to: fishDirectory.appendingPathComponent("ghostty-shell-integration.fish"))

        let inherited = [
            "KEEP": "unchanged",
            "ZDOTDIR": "/Users/example/.config/zsh",
            "XDG_DATA_DIRS": "/opt/share",
            "GHOSTTY_SHELL_FEATURES": "cursor:blink"
        ]

        let zsh = ShellIntegration.env(for: "/bin/zsh", resourceDirectory: root, inherited: inherited)
        try expect(zsh["KEEP"] == "unchanged")
        try expect(zsh["ZDOTDIR"] == zshDirectory.path)
        try expect(zsh["GHOSTTY_ZSH_ZDOTDIR"] == "/Users/example/.config/zsh")
        try expect(zsh["XDG_DATA_DIRS"] == "/opt/share")
        try expect(zsh["GHOSTTY_SHELL_FEATURES"] == "cursor:blink,title")

        let fish = ShellIntegration.env(for: "/opt/homebrew/bin/fish", resourceDirectory: root, inherited: inherited)
        try expect(fish["KEEP"] == "unchanged")
        try expect(fish["ZDOTDIR"] == "/Users/example/.config/zsh")
        try expect(fish["GHOSTTY_SHELL_INTEGRATION_XDG_DIR"] == root.appendingPathComponent("shell-integration").path)
        try expect(fish["XDG_DATA_DIRS"] == "\(root.appendingPathComponent("shell-integration").path):/opt/share")
        try expect(fish["GHOSTTY_SHELL_FEATURES"] == "cursor:blink,title")

        let bash = ShellIntegration.env(for: "/bin/bash", resourceDirectory: root, inherited: inherited)
        try expect(bash == inherited)

        let missing = ShellIntegration.env(for: "/bin/zsh", resourceDirectory: root.deletingLastPathComponent(), inherited: inherited)
        try expect(missing == inherited)

        print("ShellIntegrationCheck passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool) throws {
        guard condition() else { throw CheckError.failed }
    }

    private enum CheckError: Error {
        case failed
    }
}
