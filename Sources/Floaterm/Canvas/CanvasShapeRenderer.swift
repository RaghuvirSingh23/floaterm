import AppKit

struct CanvasShapeRenderer {
    static func draw(shape: CanvasShape, in ctx: CGContext, transform: CanvasTransform) {
        let screen = transform.worldToScreen(wx: shape.x, wy: shape.y)
        let sw = shape.w * transform.scale
        let sh = shape.h * transform.scale
        let rect = CGRect(x: screen.x, y: screen.y, width: sw, height: sh)
        let color = nsColor(from: shape.color)

        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(shape.strokeWidth * transform.scale)

        if shape.selected {
            ctx.setLineDash(phase: 0, lengths: [4, 3])
        }

        switch shape.type {
        case .rect:
            ctx.stroke(rect)
        case .circle:
            ctx.strokeEllipse(in: rect)
        case .arrow:
            let start = CGPoint(x: screen.x, y: screen.y)
            let end = CGPoint(x: screen.x + sw, y: screen.y + sh)
            drawArrow(from: start, to: end, in: ctx, scale: transform.scale)
        case .text:
            let font = NSFont.systemFont(ofSize: 14 * transform.scale)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let str = shape.text.isEmpty ? "Text" : shape.text
            (str as NSString).draw(at: CGPoint(x: screen.x, y: screen.y), withAttributes: attrs)
        case .freehand:
            guard shape.points.count >= 2 else { break }
            let first = transform.worldToScreen(wx: shape.points[0].x, wy: shape.points[0].y)
            ctx.move(to: CGPoint(x: first.x, y: first.y))
            for i in 1..<shape.points.count {
                let p = transform.worldToScreen(wx: shape.points[i].x, wy: shape.points[i].y)
                ctx.addLine(to: CGPoint(x: p.x, y: p.y))
            }
            ctx.strokePath()
        }

        ctx.setLineDash(phase: 0, lengths: [])
        ctx.restoreGState()
    }

    static func drawPreview(type: ShapeType, rect: NSRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(Colors.accent.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])

        switch type {
        case .rect:
            ctx.stroke(rect)
        case .circle:
            ctx.strokeEllipse(in: rect)
        case .arrow:
            let start = CGPoint(x: rect.minX, y: rect.minY)
            let end = CGPoint(x: rect.maxX, y: rect.maxY)
            drawArrow(from: start, to: end, in: ctx, scale: 1)
        case .text:
            ctx.stroke(rect)
        case .freehand:
            break // freehand preview drawn as path, not rect
        }

        ctx.setLineDash(phase: 0, lengths: [])
        ctx.restoreGState()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, in ctx: CGContext, scale: CGFloat) {
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        // Arrowhead
        let headLen: CGFloat = 12 * scale
        let angle = atan2(end.y - start.y, end.x - start.x)
        let a1 = angle + .pi * 0.8
        let a2 = angle - .pi * 0.8
        ctx.move(to: end)
        ctx.addLine(to: CGPoint(x: end.x + headLen * cos(a1), y: end.y + headLen * sin(a1)))
        ctx.move(to: end)
        ctx.addLine(to: CGPoint(x: end.x + headLen * cos(a2), y: end.y + headLen * sin(a2)))
        ctx.strokePath()
    }

    private static func nsColor(from hex: String) -> NSColor {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard let val = Int(str, radix: 16) else { return .green }
        return NSColor(hex: val)
    }
}
