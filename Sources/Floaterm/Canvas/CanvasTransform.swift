import Foundation

struct CanvasTransform {
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1.0

    func screenToWorld(sx: CGFloat, sy: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let x = (sx - offsetX) / scale
        let y = (sy - offsetY) / scale
        return (x, y)
    }

    func worldToScreen(wx: CGFloat, wy: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let x = wx * scale + offsetX
        let y = wy * scale + offsetY
        return (x, y)
    }

    mutating func pan(dx: CGFloat, dy: CGFloat) {
        offsetX += dx
        offsetY += dy
    }

    mutating func zoom(factor: CGFloat, centerX: CGFloat, centerY: CGFloat) {
        let before = screenToWorld(sx: centerX, sy: centerY)
        scale = min(Dimensions.maxZoom, max(Dimensions.minZoom, scale * factor))
        let after = screenToWorld(sx: centerX, sy: centerY)
        offsetX += (after.x - before.x) * scale
        offsetY += (after.y - before.y) * scale
    }

    mutating func reset() {
        offsetX = 0
        offsetY = 0
        scale = 1.0
    }
}

extension CanvasTransform: Codable {
    enum CodingKeys: String, CodingKey {
        case offsetX, offsetY, scale
    }
}
