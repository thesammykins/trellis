import SwiftUI

@MainActor final class ThemeState: ObservableObject {
    static let shared = ThemeState()
    @Published private(set) var theme: AppTheme?
    var applyTerminal: ((AppTheme?) throws -> Void)?
    init() {
        if UserDefaults.standard.string(forKey: ThemeSelection.defaultsKey) != nil {
            theme = ThemeCatalog.load(customDirectory: ThemeCatalog.customThemesDirectory).themes.first { $0.id == ThemeSelection.load() }
        }
    }
    func apply(_ theme: AppTheme) throws {
        guard theme.validationError == nil else { throw ThemeError.invalid("Invalid theme") }
        try applyTerminal?(theme)
        ThemeSelection.save(theme.id)
        self.theme = theme
    }
    func reset() throws {
        try applyTerminal?(nil)
        UserDefaults.standard.removeObject(forKey: ThemeSelection.defaultsKey)
        theme = nil
    }
}

extension Color {
    static func themeHex(_ value: String) -> Color {
        let rgb = UInt32(value, radix: 16) ?? 0
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

private struct TrellisSecondaryKey: EnvironmentKey { static let defaultValue = Color.secondary }
private struct TrellisBorderKey: EnvironmentKey { static let defaultValue = Color(nsColor: .separatorColor) }
extension EnvironmentValues {
    var trellisSecondary: Color {
        get { self[TrellisSecondaryKey.self] }
        set { self[TrellisSecondaryKey.self] = newValue }
    }
    var trellisBorder: Color {
        get { self[TrellisBorderKey.self] }
        set { self[TrellisBorderKey.self] = newValue }
    }
}
