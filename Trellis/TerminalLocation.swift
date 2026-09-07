import Foundation

/// A terminal-reported location is navigation context, never a grant of agent access.
struct TerminalLocation: Equatable {
    let localURL: URL?
    let label: String
    let unavailableReason: String?
    let summary: String

    init(reportedPath: String?, launchDirectory: URL, remoteHost: String?, running: Bool) {
        if let remoteHost {
            localURL = nil; label = "Remote folder"
            unavailableReason = "File browsing is not available for SSH · " + remoteHost
            summary = "SSH · " + remoteHost
        } else if running, let reportedPath {
            if let path = Self.validatedPath(reportedPath) {
                localURL = URL(fileURLWithPath: path).standardizedFileURL
                label = "Current folder"; unavailableReason = nil
                summary = "Current folder · " + path
            } else {
                localURL = nil; label = "Folder unavailable"
                unavailableReason = "The terminal reported an invalid folder. Refresh after changing directory."
                summary = "Current folder unknown"
            }
        } else {
            localURL = launchDirectory.standardizedFileURL
            label = "Started in"; unavailableReason = nil
            summary = "Started in · " + launchDirectory.path
        }
    }

    static func validatedPath(_ path: String) -> String? {
        guard path.hasPrefix("/"), path.utf8.count <= 4096,
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return path
    }
}
