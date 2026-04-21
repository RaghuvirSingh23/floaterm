import AppKit
import SwiftUI

enum FloatermResolvedAppearance: Equatable {
    case dark
    case light

    init(mode: AppAppearanceMode, effectiveAppearance: NSAppearance) {
        switch mode {
        case .dark:
            self = .dark
        case .light:
            self = .light
        case .system:
            let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            self = match == .darkAqua ? .dark : .light
        }
    }

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }
}

struct FloatermTheme: Equatable {
    let appearance: FloatermResolvedAppearance

    init(appearance: FloatermResolvedAppearance) {
        self.appearance = appearance
    }

    init(mode: AppAppearanceMode, effectiveAppearance: NSAppearance) {
        self.appearance = FloatermResolvedAppearance(mode: mode, effectiveAppearance: effectiveAppearance)
    }

    init(colorScheme: ColorScheme) {
        self.appearance = FloatermResolvedAppearance(colorScheme: colorScheme)
    }

    var canvasBackground: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.045, green: 0.06, blue: 0.085, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.95, green: 0.956, blue: 0.97, alpha: 1)
        }
    }

    var gridMinor: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.05)
        case .light:
            return NSColor(calibratedRed: 0.28, green: 0.34, blue: 0.46, alpha: 0.10)
        }
    }

    var gridMajor: NSColor {
        switch appearance {
        case .dark:
            return NSColor.systemMint.withAlphaComponent(0.08)
        case .light:
            return NSColor(calibratedRed: 0.24, green: 0.50, blue: 0.92, alpha: 0.16)
        }
    }

    var toolbarBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.08)
        case .light:
            return NSColor.black.withAlphaComponent(0.10)
        }
    }

    var toolbarShadow: NSColor {
        switch appearance {
        case .dark:
            return NSColor.black.withAlphaComponent(0.24)
        case .light:
            return NSColor.black.withAlphaComponent(0.14)
        }
    }

    var toolbarPrimaryText: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white
        case .light:
            return NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1)
        }
    }

    var toolbarSecondaryText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.72, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.39, green: 0.44, blue: 0.53, alpha: 1)
        }
    }

    var toolbarDivider: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.08)
        case .light:
            return NSColor.black.withAlphaComponent(0.08)
        }
    }

    var toolbarControlFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.06)
        case .light:
            return NSColor.black.withAlphaComponent(0.045)
        }
    }

    var toolbarSelectedFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white
        case .light:
            return NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.26, alpha: 0.96)
        }
    }

    var toolbarSelectedText: NSColor {
        switch appearance {
        case .dark:
            return .black
        case .light:
            return .white
        }
    }

    var selectionBadgeFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.05)
        case .light:
            return NSColor.black.withAlphaComponent(0.04)
        }
    }

    var toolbarDeleteText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.98, green: 0.53, blue: 0.50, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.78, green: 0.24, blue: 0.22, alpha: 1)
        }
    }

    var toolbarDeleteFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.systemRed.withAlphaComponent(0.10)
        case .light:
            return NSColor(calibratedRed: 0.90, green: 0.18, blue: 0.15, alpha: 0.12)
        }
    }

    var toolbarBroadcastText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.76, green: 0.90, blue: 1.0, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.08, green: 0.46, blue: 0.68, alpha: 1)
        }
    }

    var toolbarBroadcastFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.systemCyan.withAlphaComponent(0.12)
        case .light:
            return NSColor(calibratedRed: 0.13, green: 0.64, blue: 0.89, alpha: 0.12)
        }
    }

    var toolbarBroadcastEnabledText: NSColor {
        switch appearance {
        case .dark:
            return .black
        case .light:
            return .white
        }
    }

    var toolbarBroadcastEnabledFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.74, green: 0.90, blue: 1.0, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.10, green: 0.56, blue: 0.82, alpha: 0.94)
        }
    }

    var toolbarFrameText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 1.0, green: 0.83, blue: 0.52, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.76, green: 0.46, blue: 0.05, alpha: 1)
        }
    }

    var toolbarFrameFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.systemOrange.withAlphaComponent(0.11)
        case .light:
            return NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.14, alpha: 0.14)
        }
    }

    var minimapBackground: NSColor {
        switch appearance {
        case .dark:
            return NSColor.black.withAlphaComponent(0.32)
        case .light:
            return NSColor.white.withAlphaComponent(0.78)
        }
    }

    var minimapBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.10)
        case .light:
            return NSColor.black.withAlphaComponent(0.10)
        }
    }

    var minimapCanvasFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.02)
        case .light:
            return NSColor.black.withAlphaComponent(0.03)
        }
    }

    var minimapFrameStroke: NSColor {
        switch appearance {
        case .dark:
            return NSColor.systemOrange.withAlphaComponent(0.55)
        case .light:
            return NSColor.systemOrange.withAlphaComponent(0.70)
        }
    }

    var minimapFrameSelectedStroke: NSColor {
        switch appearance {
        case .dark:
            return NSColor.systemOrange.withAlphaComponent(0.95)
        case .light:
            return NSColor.systemOrange.withAlphaComponent(0.98)
        }
    }

    var minimapNodeFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.14)
        case .light:
            return NSColor.black.withAlphaComponent(0.09)
        }
    }

    var minimapNodeSelectedFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.26)
        case .light:
            return NSColor(calibratedRed: 0.18, green: 0.27, blue: 0.41, alpha: 0.18)
        }
    }

    var minimapNodeStroke: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.28)
        case .light:
            return NSColor.black.withAlphaComponent(0.24)
        }
    }

    var minimapNodeSelectedStroke: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.75, green: 0.94, blue: 1.0, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.18, green: 0.49, blue: 0.95, alpha: 1)
        }
    }

    var minimapTextFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.38, green: 0.78, blue: 1.0, alpha: 0.32)
        case .light:
            return NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.86, alpha: 0.22)
        }
    }

    var minimapTextSelectedFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.60, green: 0.92, blue: 1.0, alpha: 0.55)
        case .light:
            return NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.86, alpha: 0.38)
        }
    }

    var minimapViewportFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.06)
        case .light:
            return NSColor.black.withAlphaComponent(0.05)
        }
    }

    var minimapViewportStroke: NSColor {
        switch appearance {
        case .dark:
            return NSColor.white.withAlphaComponent(0.95)
        case .light:
            return NSColor.black.withAlphaComponent(0.80)
        }
    }

    var frameBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.36, alpha: 0.92)
        case .light:
            return NSColor(calibratedRed: 0.46, green: 0.50, blue: 0.57, alpha: 0.92)
        }
    }

    var frameSelectedBorder: NSColor {
        NSColor(calibratedRed: 0.96, green: 0.74, blue: 0.33, alpha: 0.96)
    }

    var frameFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 1, alpha: 0.025)
        case .light:
            return NSColor.white.withAlphaComponent(0.38)
        }
    }

    var frameSelectedFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.99, green: 0.65, blue: 0.16, alpha: 0.08)
        case .light:
            return NSColor(calibratedRed: 0.99, green: 0.71, blue: 0.26, alpha: 0.11)
        }
    }

    var frameBadgeFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 0.96)
        case .light:
            return NSColor(calibratedRed: 0.97, green: 0.974, blue: 0.982, alpha: 0.98)
        }
    }

    var frameBadgeBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.30, alpha: 0.92)
        case .light:
            return NSColor(calibratedRed: 0.78, green: 0.81, blue: 0.86, alpha: 0.95)
        }
    }

    var frameBadgeSelectedBorder: NSColor {
        NSColor(calibratedRed: 0.96, green: 0.74, blue: 0.33, alpha: 0.55)
    }

    var frameTitleText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.78, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.31, alpha: 1)
        }
    }

    var frameTitleSelectedText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.92, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1)
        }
    }

    var frameEditButton: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.62, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.47, green: 0.52, blue: 0.61, alpha: 1)
        }
    }

    var frameEditButtonSelected: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.97, green: 0.80, blue: 0.43, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.86, green: 0.58, blue: 0.12, alpha: 1)
        }
    }

    var selectionOutline: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.84, alpha: 0.92)
        case .light:
            return NSColor(calibratedRed: 0.28, green: 0.34, blue: 0.44, alpha: 0.82)
        }
    }

    var terminalShellBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.26, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.76, green: 0.79, blue: 0.84, alpha: 1)
        }
    }

    var terminalSelectedShellBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.34, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.64, alpha: 1)
        }
    }

    var terminalShellFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 0.98)
        case .light:
            return NSColor(calibratedRed: 0.96, green: 0.968, blue: 0.978, alpha: 0.98)
        }
    }

    var terminalTitlebarFill: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 0.98)
        case .light:
            return NSColor(calibratedRed: 0.90, green: 0.915, blue: 0.938, alpha: 0.99)
        }
    }

    var terminalSeparator: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.30, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.78, green: 0.81, blue: 0.86, alpha: 1)
        }
    }

    var terminalContentBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.20, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.80, green: 0.83, blue: 0.88, alpha: 1)
        }
    }

    var terminalSelectedContentBorder: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.25, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.68, green: 0.72, blue: 0.78, alpha: 1)
        }
    }

    var terminalTitleText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.70, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.23, green: 0.27, blue: 0.34, alpha: 1)
        }
    }

    var terminalTitleSelectedText: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.84, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.24, alpha: 1)
        }
    }

    var terminalCloseFill: NSColor {
        NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.33, alpha: 0.95)
    }

    var terminalCloseSelectedFill: NSColor {
        NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.33, alpha: 1)
    }

    var terminalCloseGlyph: NSColor {
        NSColor(calibratedRed: 0.34, green: 0.12, blue: 0.11, alpha: 0.96)
    }

    var terminalEditButton: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.66, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.48, green: 0.52, blue: 0.61, alpha: 1)
        }
    }

    var terminalEditButtonSelected: NSColor {
        switch appearance {
        case .dark:
            return NSColor(calibratedWhite: 0.80, alpha: 1)
        case .light:
            return NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.40, alpha: 1)
        }
    }

    var canvasTextColor: NSColor {
        switch appearance {
        case .dark:
            return .white
        case .light:
            return NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.22, alpha: 1)
        }
    }

    var terminalAppearanceName: String {
        switch appearance {
        case .dark:
            return "dark"
        case .light:
            return "light"
        }
    }
}

extension AppAppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .light:
            return NSAppearance(named: .aqua)
        }
    }
}
