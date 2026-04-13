import AppKit

enum Theme {
    case light, dark
}

enum Tool: String, CaseIterable {
    case draw, hand, spawn
    case shapeRect, shapeCircle, shapeArrow, shapeText, shapeFreehand
}

struct Colors {
    // Light theme
    static let lightBg = NSColor(hex: 0xFFFFFF)
    static let lightGrid = NSColor(hex: 0xE0E0E0)
    static let lightSurface = NSColor(hex: 0xFFFFFF)
    static let lightBorder = NSColor(hex: 0xE0E0E0)
    static let lightText = NSColor(hex: 0x333333)
    static let lightTextSecondary = NSColor(hex: 0x666666)
    static let lightTextMuted = NSColor(hex: 0x999999)

    // Dark theme
    static let darkBg = NSColor(hex: 0x0A0A0A)
    static let darkGrid = NSColor(hex: 0x1E1E1E)
    static let darkSurface = NSColor(hex: 0x141414)
    static let darkBorder = NSColor(white: 1.0, alpha: 0.12)
    static let darkText = NSColor(hex: 0xE5E5E5)
    static let darkTextSecondary = NSColor(hex: 0xA0A0A0)
    static let darkTextMuted = NSColor(hex: 0x666666)

    // Shared
    static let accent = NSColor(hex: 0x22C55E)
    static let focusBorder = NSColor(hex: 0x22C55E)
    static let terminalBg = NSColor(hex: 0x0F0F23)
    static let titleBarBg = NSColor(hex: 0x16213E)
    static let titleBarText = NSColor(hex: 0x8888AA)
    static let terminalBorder = NSColor(hex: 0x4A4A6A)

    static func bg(for theme: Theme) -> NSColor { theme == .dark ? darkBg : lightBg }
    static func grid(for theme: Theme) -> NSColor { theme == .dark ? darkGrid : lightGrid }
    static func surface(for theme: Theme) -> NSColor { theme == .dark ? darkSurface : lightSurface }
    static func border(for theme: Theme) -> NSColor { theme == .dark ? darkBorder : lightBorder }
    static func text(for theme: Theme) -> NSColor { theme == .dark ? darkText : lightText }
    static func textSecondary(for theme: Theme) -> NSColor { theme == .dark ? darkTextSecondary : lightTextSecondary }
}

struct Dimensions {
    static let gridSize: CGFloat = 40
    static let snapThreshold: CGFloat = 10
    static let minTerminalWidth: CGFloat = 300
    static let minTerminalHeight: CGFloat = 200
    static let titleBarHeight: CGFloat = 24
    static let minZoom: CGFloat = 0.05
    static let maxZoom: CGFloat = 5.0
    static let scrollbackLimit = 50_000
    static let spawnCascadeOffset: CGFloat = 30
    static let defaultTerminalWidth: CGFloat = 500
    static let defaultTerminalHeight: CGFloat = 350
    static let defaultWindowWidth: CGFloat = 1200
    static let defaultWindowHeight: CGFloat = 800
    static let drawMinSize: CGFloat = 50
    static let resizeHandleSize: CGFloat = 6
    static let cornerHandleSize: CGFloat = 12
}

// MARK: - NSColor hex extension

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
