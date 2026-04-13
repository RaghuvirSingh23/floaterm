import AppKit

final class CanvasView: NSView {
    var transform = CanvasTransform() {
        didSet { needsDisplay = true }
    }
    var theme: Theme = .light {
        didSet { needsDisplay = true }
    }
    var shapes: [CanvasShape] = [] {
        didSet { needsDisplay = true }
    }
    var drawPreview: NSRect? {
        didSet { needsDisplay = true }
    }
    var shapePreview: (type: ShapeType, rect: NSRect)? {
        didSet { needsDisplay = true }
    }

    // Event callbacks (wired by AppDelegate)
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onScrollWheel: ((NSEvent) -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        print("[Canvas] mouseDown at window=\(event.locationInWindow) view=\(convert(event.locationInWindow, from: nil))")
        onMouseDown?(event)
    }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) {
        print("[Canvas] mouseUp at window=\(event.locationInWindow)")
        onMouseUp?(event)
    }
    override func scrollWheel(with event: NSEvent) {
        print("[Canvas] scrollWheel deltaX=\(event.scrollingDeltaX) deltaY=\(event.scrollingDeltaY) cmd=\(event.modifierFlags.contains(.command)) opt=\(event.modifierFlags.contains(.option))")
        onScrollWheel?(event)
    }
    override func keyDown(with event: NSEvent) {
        print("[Canvas] keyDown key=\(event.charactersIgnoringModifiers ?? "?")")
        onKeyDown?(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height

        // Background
        ctx.setFillColor(Colors.bg(for: theme).cgColor)
        ctx.fill(bounds)

        // Grid lines
        let gridSize = Dimensions.gridSize * transform.scale
        guard gridSize > 8 else { return }

        ctx.setStrokeColor(Colors.grid(for: theme).cgColor)
        ctx.setLineWidth(0.5)

        let startX = transform.offsetX.truncatingRemainder(dividingBy: gridSize)
        let startY = transform.offsetY.truncatingRemainder(dividingBy: gridSize)

        // Vertical lines
        var x = startX
        while x < w {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: h))
            x += gridSize
        }
        // Horizontal lines
        var y = startY
        while y < h {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: w, y: y))
            y += gridSize
        }
        ctx.strokePath()

        // Draw shapes
        for shape in shapes {
            CanvasShapeRenderer.draw(shape: shape, in: ctx, transform: transform)
        }

        // Shape preview
        if let preview = shapePreview {
            CanvasShapeRenderer.drawPreview(type: preview.type, rect: preview.rect, in: ctx)
        }

        // Draw preview rect (green dashed)
        if let preview = drawPreview {
            ctx.setStrokeColor(Colors.accent.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(preview)
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }
}
