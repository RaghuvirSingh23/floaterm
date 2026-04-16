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

struct CanvasCamera: Equatable {
    var zoom: CGFloat = 1
    var pan: CGPoint = .zero
}

struct TerminalNode: Identifiable, Equatable {
    let id: UUID
    var title: String
    var frame: CGRect
}

struct CanvasTextItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var frame: CGRect
    var wrapWidth: CGFloat?
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
