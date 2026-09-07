import Foundation
import Combine

@MainActor
final class TerminalState: ObservableObject {
    @Published var workingDirectory: String?
    @Published var title = "Shell"
    @Published var isSearching = false
    @Published var query = ""
    @Published var matchCount: Int?
    @Published var selectedMatch: Int?
    @Published var exitCode: UInt32?
    @Published var warning: String?
    @Published var secureInputActive = false
    var secureInputRequested = false
    var focused = false
}
