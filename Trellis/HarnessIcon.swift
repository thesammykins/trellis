import SwiftUI

@MainActor
struct HarnessIcon: View {
    let profile: LaunchProfile
    @Environment(\.colorScheme) private var scheme

    private static let artwork: [String: NSImage] = {
        var images: [String: NSImage] = [:]
        for name in ["codex-openai", "opencode-on-dark", "opencode-on-light"] {
            if let path = Bundle.main.path(forResource: name, ofType: "svg", inDirectory: "harnesses"),
               let image = NSImage(contentsOfFile: path) {
                image.isTemplate = name == "codex-openai"
                images[name] = image
            }
        }
        return images
    }()

    static func menuImage(_ profile: LaunchProfile, dark: Bool) -> NSImage {
        let name = profile == .codex ? "codex-openai" : profile == .opencode ? (dark ? "opencode-on-dark" : "opencode-on-light") : ""
        let original = artwork[name] ?? NSImage(systemSymbolName: profile == .claude ? "c.circle" : profile == .gemini ? "g.circle" : profile == .pi ? "p.circle" : "terminal", accessibilityDescription: profile.title)!
        let image = original.copy() as! NSImage
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    var body: some View {
        Group {
            if let image = Self.artwork[artworkName] {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: fallbackSymbol).resizable().scaledToFit()
            }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }

    private var fallbackSymbol: String {
        switch profile {
        case .shell: "terminal"
        case .claude: "c.circle"
        case .gemini: "g.circle"
        case .pi: "p.circle"
        default: "sparkles"
        }
    }

    private var artworkName: String {
        switch profile {
        case .codex: "codex-openai"
        case .opencode: scheme == .dark ? "opencode-on-dark" : "opencode-on-light"
        default: ""
        }
    }
}
