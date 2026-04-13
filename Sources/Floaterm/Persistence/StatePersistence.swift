import Foundation

struct PersistedState: Codable {
    var canvas: CanvasTransform
    var boxes: [TerminalBox]
    var shapes: [CanvasShape]

    init(canvas: CanvasTransform = CanvasTransform(), boxes: [TerminalBox] = [], shapes: [CanvasShape] = []) {
        self.canvas = canvas
        self.boxes = boxes
        self.shapes = shapes
    }
}

struct StatePersistence {
    static let stateDir = NSHomeDirectory() + "/.floaterm"
    static let statePath = stateDir + "/state.json"

    static func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    static func save(_ state: PersistedState) {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: URL(fileURLWithPath: statePath))
    }
}
