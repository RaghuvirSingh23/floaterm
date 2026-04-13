import Foundation

struct TerminalBox: Identifiable, Codable, Equatable {
    var id: String
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var label: String
    var focused: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, x, y, w, h, label
    }

    init(id: String? = nil, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, label: String? = nil, existingIds: [String] = []) {
        let resolvedId = id ?? IdAllocator.lowestAvailable(existing: existingIds)
        self.id = resolvedId
        self.x = x
        self.y = y
        self.w = max(w, Dimensions.minTerminalWidth)
        self.h = max(h, Dimensions.minTerminalHeight)
        self.label = label ?? "terminal-\(resolvedId)"
    }

    static func == (lhs: TerminalBox, rhs: TerminalBox) -> Bool {
        lhs.id == rhs.id
    }
}
