import AppKit
import Foundation

enum CanvasTool: String, CaseIterable, Identifiable {
    case select
    case terminal
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select:
            return "Select"
        case .terminal:
            return "Terminal"
        case .text:
            return "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .terminal:
            return "terminal"
        case .text:
            return "textformat"
        }
    }
}

struct CanvasCamera: Equatable, Codable {
    var zoom: CGFloat = 1
    var pan: CGPoint = .zero
}

struct TerminalNode: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var frame: CGRect
}

struct CanvasTextItem: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String
    var frame: CGRect
    var wrapWidth: CGFloat?
}

enum TerminalPersistenceMode: String, CaseIterable, Codable, Identifiable {
    case keepRunningUntilShutdown
    case restoreHistoryOnReopen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepRunningUntilShutdown:
            return "Keep Live"
        case .restoreHistoryOnReopen:
            return "Restore History"
        }
    }

    var summary: String {
        switch self {
        case .keepRunningUntilShutdown:
            return "Closing the window hides the app and keeps live terminals running until shutdown or force quit."
        case .restoreHistoryOnReopen:
            return "Closing or quitting stops the shells. Reopening restores each terminal transcript, then starts a fresh shell."
        }
    }
}

struct WorkspaceSnapshot: Codable, Equatable {
    var nodes: [TerminalNode]
    var textItems: [CanvasTextItem]
    var camera: CanvasCamera
    var terminalCounter: Int
}

struct CanvasSnapState: Equatable {
    var x: CGFloat?
    var y: CGFloat?

    static let none = CanvasSnapState(x: nil, y: nil)

    var isActive: Bool {
        x != nil || y != nil
    }
}

enum ResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}
