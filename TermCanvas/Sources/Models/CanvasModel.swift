import AppKit
import Foundation

enum CanvasTool: String, CaseIterable, Identifiable {
    case select
    case terminal
    case frame
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select:
            return "Select"
        case .terminal:
            return "Terminal"
        case .frame:
            return "Frame"
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
        case .frame:
            return "square.on.square"
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

struct CanvasFrameItem: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var frame: CGRect
    var childIDs: [UUID]
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
    var frameItems: [CanvasFrameItem]
    var textItems: [CanvasTextItem]
    var camera: CanvasCamera
    var terminalCounter: Int
    var frameCounter: Int

    init(
        nodes: [TerminalNode],
        frameItems: [CanvasFrameItem] = [],
        textItems: [CanvasTextItem],
        camera: CanvasCamera,
        terminalCounter: Int,
        frameCounter: Int = 1
    ) {
        self.nodes = nodes
        self.frameItems = frameItems
        self.textItems = textItems
        self.camera = camera
        self.terminalCounter = terminalCounter
        self.frameCounter = frameCounter
    }

    private enum CodingKeys: String, CodingKey {
        case nodes
        case frameItems
        case textItems
        case camera
        case terminalCounter
        case frameCounter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decodeIfPresent([TerminalNode].self, forKey: .nodes) ?? []
        frameItems = try container.decodeIfPresent([CanvasFrameItem].self, forKey: .frameItems) ?? []
        textItems = try container.decodeIfPresent([CanvasTextItem].self, forKey: .textItems) ?? []
        camera = try container.decodeIfPresent(CanvasCamera.self, forKey: .camera) ?? CanvasCamera()
        terminalCounter = try container.decodeIfPresent(Int.self, forKey: .terminalCounter) ?? max(nodes.count + 1, 1)
        frameCounter = try container.decodeIfPresent(Int.self, forKey: .frameCounter) ?? max(frameItems.count + 1, 1)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes, forKey: .nodes)
        try container.encode(frameItems, forKey: .frameItems)
        try container.encode(textItems, forKey: .textItems)
        try container.encode(camera, forKey: .camera)
        try container.encode(terminalCounter, forKey: .terminalCounter)
        try container.encode(frameCounter, forKey: .frameCounter)
    }
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
