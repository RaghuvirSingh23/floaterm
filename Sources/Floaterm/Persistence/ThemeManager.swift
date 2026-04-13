import AppKit

struct ThemeManager {
    private static let key = "floaterm-theme"

    static func loadTheme() -> Theme {
        let stored = UserDefaults.standard.string(forKey: key)
        if stored == "dark" { return .dark }
        if stored == "light" { return .light }
        // Follow system preference
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    static func saveTheme(_ theme: Theme) {
        UserDefaults.standard.set(theme == .dark ? "dark" : "light", forKey: key)
    }
}
