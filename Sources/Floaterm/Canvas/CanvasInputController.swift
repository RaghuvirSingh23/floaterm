import AppKit

enum InputState {
    case idle
    case drawing(start: CGPoint)
    case panning(lastPoint: CGPoint)
    case draggingBox(id: String)
    case resizingBox(id: String, handle: String, origX: CGFloat, origY: CGFloat, origW: CGFloat, origH: CGFloat, accumDx: CGFloat, accumDy: CGFloat)
    case annotating(type: ShapeType, start: CGPoint, points: [CGPoint])
    case draggingShape(id: UUID, startWorld: CGPoint, origX: CGFloat, origY: CGFloat)
}

@MainActor
final class CanvasInputController {
    weak var canvasView: CanvasView?
    var appState: AppState!
    var onBoxCreated: ((TerminalBox) -> Void)?
    var onBoxChanged: (() -> Void)?

    private var state: InputState = .idle
    private var shiftHeld = false

    // MARK: - Canvas mouse events (from CanvasView)

    func mouseDown(with event: NSEvent, in view: NSView) {
        let loc = view.convert(event.locationInWindow, from: nil)
        let world = appState.transform.screenToWorld(sx: loc.x, sy: loc.y)
        shiftHeld = event.modifierFlags.contains(.shift)
        print("[Input] mouseDown tool=\(appState.activeTool) loc=\(loc) world=\(world)")

        switch appState.activeTool {
        case .hand:
            state = .panning(lastPoint: loc)
        case .draw:
            state = .drawing(start: loc)
        case .spawn:
            break
        case .shapeRect, .shapeCircle, .shapeArrow, .shapeText, .shapeFreehand:
            let shapeType = shapeTypeForTool(appState.activeTool)
            if shapeType == .freehand {
                state = .annotating(type: .freehand, start: loc, points: [CGPoint(x: world.x, y: world.y)])
            } else {
                state = .annotating(type: shapeType, start: loc, points: [])
            }
        }
    }

    func mouseDragged(with event: NSEvent, in view: NSView) {
        let loc = view.convert(event.locationInWindow, from: nil)

        switch state {
        case .panning(let last):
            let dx = loc.x - last.x
            let dy = loc.y - last.y
            appState.transform.pan(dx: dx, dy: dy)
            canvasView?.transform = appState.transform
            onBoxChanged?()
            state = .panning(lastPoint: loc)

        case .drawing(let start):
            let rect = NSRect(
                x: min(start.x, loc.x), y: min(start.y, loc.y),
                width: abs(loc.x - start.x), height: abs(loc.y - start.y)
            )
            canvasView?.drawPreview = rect

        case .annotating(let type, let start, var points):
            if type == .freehand {
                let world = appState.transform.screenToWorld(sx: loc.x, sy: loc.y)
                points.append(CGPoint(x: world.x, y: world.y))
                state = .annotating(type: type, start: start, points: points)
                canvasView?.needsDisplay = true
            } else {
                let rect = NSRect(
                    x: min(start.x, loc.x), y: min(start.y, loc.y),
                    width: abs(loc.x - start.x), height: abs(loc.y - start.y)
                )
                canvasView?.shapePreview = (type: type, rect: rect)
            }

        case .draggingShape(let id, let startWorld, let origX, let origY):
            let world = appState.transform.screenToWorld(sx: loc.x, sy: loc.y)
            guard let idx = appState.shapes.firstIndex(where: { $0.id == id }) else { return }
            appState.shapes[idx].x = origX + (world.x - startWorld.x)
            appState.shapes[idx].y = origY + (world.y - startWorld.y)
            canvasView?.shapes = appState.shapes
            onBoxChanged?()

        default:
            break
        }
    }

    func mouseUp(with event: NSEvent, in view: NSView) {
        let loc = view.convert(event.locationInWindow, from: nil)

        switch state {
        case .drawing(let start):
            canvasView?.drawPreview = nil
            let rect = NSRect(
                x: min(start.x, loc.x), y: min(start.y, loc.y),
                width: abs(loc.x - start.x), height: abs(loc.y - start.y)
            )
            if rect.width >= Dimensions.drawMinSize && rect.height >= Dimensions.drawMinSize {
                let worldStart = appState.transform.screenToWorld(sx: rect.minX, sy: rect.minY)
                var box = TerminalBox(
                    x: worldStart.x, y: worldStart.y,
                    w: rect.width / appState.transform.scale,
                    h: rect.height / appState.transform.scale,
                    existingIds: appState.existingIds
                )
                if !shiftHeld {
                    let snap = GridSnap.snapPoint(CGPoint(x: box.x, y: box.y))
                    if snap.snapped { GridSnap.hapticFeedback() }
                    box.x = snap.point.x
                    box.y = snap.point.y
                }
                appState.addBox(box)
                onBoxCreated?(box)
            }

        case .annotating(let type, let start, let points):
            canvasView?.shapePreview = nil
            if type == .freehand {
                if points.count >= 2 {
                    let bounds = boundingBox(of: points)
                    var shape = CanvasShape(type: .freehand, x: bounds.minX, y: bounds.minY, w: bounds.width, h: bounds.height)
                    shape.points = points
                    appState.addShape(shape)
                    canvasView?.shapes = appState.shapes
                    onBoxChanged?()
                }
            } else {
                let rect = NSRect(
                    x: min(start.x, loc.x), y: min(start.y, loc.y),
                    width: abs(loc.x - start.x), height: abs(loc.y - start.y)
                )
                if rect.width > 5 || rect.height > 5 {
                    let worldStart = appState.transform.screenToWorld(sx: rect.minX, sy: rect.minY)
                    let shape = CanvasShape(
                        type: type,
                        x: worldStart.x, y: worldStart.y,
                        w: rect.width / appState.transform.scale,
                        h: rect.height / appState.transform.scale
                    )
                    appState.addShape(shape)
                    canvasView?.shapes = appState.shapes
                    onBoxChanged?()
                }
            }

        default:
            break
        }

        state = .idle
    }

    // MARK: - Scroll (zoom + pan)

    func scrollWheel(with event: NSEvent, in view: NSView) {
        print("[Input] scrollWheel scrollDeltaX=\(event.scrollingDeltaX) scrollDeltaY=\(event.scrollingDeltaY) cmd=\(event.modifierFlags.contains(.command)) opt=\(event.modifierFlags.contains(.option)) tool=\(appState.activeTool)")
        if event.modifierFlags.contains(.command) {
            let loc = view.convert(event.locationInWindow, from: nil)
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.05 : 0.95
            appState.transform.zoom(factor: factor, centerX: loc.x, centerY: loc.y)
            canvasView?.transform = appState.transform
            onBoxChanged?()
            print("[Input] zoom -> scale=\(appState.transform.scale)")
        } else if appState.activeTool == .hand || event.modifierFlags.contains(.option) {
            appState.transform.pan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            canvasView?.transform = appState.transform
            onBoxChanged?()
            print("[Input] pan -> offset=(\(appState.transform.offsetX), \(appState.transform.offsetY))")
        } else {
            print("[Input] scrollWheel IGNORED — tool=\(appState.activeTool), no cmd/opt modifier")
        }
    }

    // MARK: - Keyboard

    func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "d": appState.activeTool = .draw
        case "h": appState.activeTool = .hand
        default: break
        }

        if event.keyCode == 51 { // Backspace
            appState.shapes.removeAll { $0.selected }
            canvasView?.shapes = appState.shapes
            onBoxChanged?()
        }
    }

    // MARK: - Box drag (from TitleBarView via TerminalBoxView)
    // Uses event.deltaX/deltaY which are screen-direction pixel deltas — no coordinate space confusion.

    func startDragBox(id: String, windowPoint: NSPoint) {
        shiftHeld = NSEvent.modifierFlags.contains(.shift)
        appState.focusBox(id: id)
        state = .draggingBox(id: id)
    }

    func dragBoxMoved(with event: NSEvent) {
        guard case .draggingBox(let id) = state else { return }
        guard let idx = appState.boxIndex(id: id) else { return }

        let dx = event.deltaX / appState.transform.scale
        let dy = event.deltaY / appState.transform.scale
        print("[Input] dragBoxMoved id=\(id) deltaX=\(event.deltaX) deltaY=\(event.deltaY) scale=\(appState.transform.scale) dx=\(dx) dy=\(dy)")

        var newX = appState.boxes[idx].x + dx
        var newY = appState.boxes[idx].y + dy

        if !shiftHeld {
            let snapResult = GridSnap.snapPoint(CGPoint(x: newX, y: newY))
            if snapResult.snapped { GridSnap.hapticFeedback() }
            newX = snapResult.point.x
            newY = snapResult.point.y
        }

        appState.boxes[idx].x = newX
        appState.boxes[idx].y = newY
        onBoxChanged?()
    }

    func dragBoxEnded(with event: NSEvent) {
        state = .idle
        onBoxChanged?()
    }

    // MARK: - Box resize (from ResizeHandleView via TerminalBoxView)

    func startResizeBox(id: String, handle: String, event: NSEvent) {
        guard let box = appState.boxes.first(where: { $0.id == id }) else { return }
        shiftHeld = event.modifierFlags.contains(.shift)
        state = .resizingBox(id: id, handle: handle, origX: box.x, origY: box.y, origW: box.w, origH: box.h, accumDx: 0, accumDy: 0)
    }

    func resizeBoxMoved(with event: NSEvent) {
        guard case .resizingBox(let id, let handle, let origX, let origY, let origW, let origH, let prevDx, let prevDy) = state else { return }
        guard let idx = appState.boxIndex(id: id) else { return }

        let accumDx = prevDx + event.deltaX / appState.transform.scale
        let accumDy = prevDy + event.deltaY / appState.transform.scale
        state = .resizingBox(id: id, handle: handle, origX: origX, origY: origY, origW: origW, origH: origH, accumDx: accumDx, accumDy: accumDy)

        var (x, y, w, h) = (origX, origY, origW, origH)

        if handle.contains("e") { w = max(Dimensions.minTerminalWidth, origW + accumDx) }
        if handle.contains("w") { x = origX + accumDx; w = max(Dimensions.minTerminalWidth, origW - accumDx) }
        if handle.contains("s") { h = max(Dimensions.minTerminalHeight, origH + accumDy) }
        if handle.contains("n") { y = origY + accumDy; h = max(Dimensions.minTerminalHeight, origH - accumDy) }

        if w < Dimensions.minTerminalWidth && handle.contains("w") { x = origX + origW - Dimensions.minTerminalWidth; w = Dimensions.minTerminalWidth }
        if h < Dimensions.minTerminalHeight && handle.contains("n") { y = origY + origH - Dimensions.minTerminalHeight; h = Dimensions.minTerminalHeight }

        appState.boxes[idx].x = x
        appState.boxes[idx].y = y
        appState.boxes[idx].w = max(Dimensions.minTerminalWidth, w)
        appState.boxes[idx].h = max(Dimensions.minTerminalHeight, h)
        onBoxChanged?()
    }

    func resizeBoxEnded(with event: NSEvent) {
        state = .idle
        onBoxChanged?()
    }

    // MARK: - Helpers

    private func shapeTypeForTool(_ tool: Tool) -> ShapeType {
        switch tool {
        case .shapeRect: return .rect
        case .shapeCircle: return .circle
        case .shapeArrow: return .arrow
        case .shapeText: return .text
        case .shapeFreehand: return .freehand
        default: return .rect
        }
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
