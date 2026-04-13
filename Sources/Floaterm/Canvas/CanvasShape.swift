import Foundation

enum ShapeType: String, Codable, CaseIterable {
    case rect, circle, arrow, text, freehand
}

struct CanvasShape: Identifiable, Codable {
    var id: UUID = UUID()
    var type: ShapeType
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var color: String = "#22C55E"  // hex string for Codable simplicity
    var strokeWidth: CGFloat = 2
    var text: String = ""          // for text annotations
    var points: [CGPoint] = []     // for freehand
    var selected: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, type, x, y, w, h, color, strokeWidth, text, points
    }

    func contains(worldPoint: CGPoint) -> Bool {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        switch type {
        case .circle:
            let cx = x + w / 2
            let cy = y + h / 2
            let rx = w / 2
            let ry = h / 2
            let dx = (worldPoint.x - cx) / rx
            let dy = (worldPoint.y - cy) / ry
            return dx * dx + dy * dy <= 1.0
        case .freehand:
            // Check proximity to any segment
            for i in 0..<max(0, points.count - 1) {
                let dist = distanceFromPointToSegment(worldPoint, points[i], points[i + 1])
                if dist < 8 { return true }
            }
            return false
        case .arrow:
            // Check proximity to line from (x,y) to (x+w, y+h)
            let dist = distanceFromPointToSegment(worldPoint, CGPoint(x: x, y: y), CGPoint(x: x + w, y: y + h))
            return dist < 8
        default:
            return rect.contains(worldPoint)
        }
    }

    private func distanceFromPointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq
        t = max(0, min(1, t))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}

// CGPoint is already Codable via CoreGraphics
