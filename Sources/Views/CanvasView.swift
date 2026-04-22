import AppKit
import SwiftUI
import WebKit

struct CanvasViewRepresentable: NSViewRepresentable {
    @ObservedObject var store: CanvasStore
    let appModel: AppModel
    let appearanceMode: AppAppearanceMode

    func makeNSView(context: Context) -> CanvasViewportView {
        let view = CanvasViewportView()
        view.apply(store: store, appModel: appModel, appearanceMode: appearanceMode)
        return view
    }

    func updateNSView(_ nsView: CanvasViewportView, context: Context) {
        nsView.apply(store: store, appModel: appModel, appearanceMode: appearanceMode)
    }
}

final class CanvasViewportView: NSView {
    private enum LayerDepth {
        static let frameBase: CGFloat = 0
        static let nodeBase: CGFloat = 10_000
        static let textBase: CGFloat = 20_000
        static let selectedBoost: CGFloat = 1_000
    }

    private enum Interaction {
        case panning(anchor: CGPoint, initialPan: CGPoint)
        case creatingTerminal(startScreen: CGPoint, currentScreen: CGPoint)
        case creatingFrame(startScreen: CGPoint, currentScreen: CGPoint)
        case marqueeSelecting(startScreen: CGPoint, currentScreen: CGPoint, appendToSelection: Bool)
    }

    private enum PreviewStyle {
        case terminalCreation
        case frameCreation
        case selection

        var fillColor: NSColor {
            switch self {
            case .terminalCreation:
                return NSColor.systemMint.withAlphaComponent(0.14)
            case .frameCreation:
                return NSColor.systemOrange.withAlphaComponent(0.10)
            case .selection:
                return NSColor.systemBlue.withAlphaComponent(0.12)
            }
        }

        var strokeColor: NSColor {
            switch self {
            case .terminalCreation:
                return NSColor.systemMint.withAlphaComponent(0.9)
            case .frameCreation:
                return NSColor.systemOrange.withAlphaComponent(0.94)
            case .selection:
                return NSColor.systemBlue.withAlphaComponent(0.96)
            }
        }

        var dashPattern: [CGFloat] {
            switch self {
            case .terminalCreation:
                return [10, 7]
            case .frameCreation:
                return [10, 6]
            case .selection:
                return [8, 5]
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .terminalCreation:
                return 18
            case .frameCreation:
                return 14
            case .selection:
                return 10
            }
        }
    }

    private weak var store: CanvasStore?
    private weak var appModel: AppModel?
    private var appearanceMode: AppAppearanceMode = .dark
    private var theme = FloatermTheme(appearance: .dark)
    private let worldView = NSView()
    private var frameViews: [UUID: CanvasFrameItemView] = [:]
    private var nodeViews: [UUID: TerminalNodeView] = [:]
    private var textViews: [UUID: CanvasTextItemView] = [:]
    private var interaction: Interaction?
    private var previewWorldRect: CGRect?
    private var previewStyle: PreviewStyle?
    private var hasBootstrappedCamera = false
    private var spacebarIsDown = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        worldView.autoresizingMask = [.width, .height]
        addSubview(worldView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateThemeIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateThemeIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        guard let store else {
            return
        }

        store.updateViewportSize(newSize)

        if !hasBootstrappedCamera, !newSize.equalTo(.zero) {
            store.bootstrapCameraIfNeeded(center: CGPoint(x: newSize.width * 0.5, y: newSize.height * 0.5))
            hasBootstrappedCamera = true
        }

        updateWorldViewTransform()
        syncElementViews()
        handlePendingTerminalFocusRequest()
        needsDisplay = true
    }

    func apply(store: CanvasStore, appModel: AppModel, appearanceMode: AppAppearanceMode) {
        self.store = store
        self.appModel = appModel
        self.appearanceMode = appearanceMode
        store.updateViewportSize(bounds.size)
        updateThemeIfNeeded()

        if !hasBootstrappedCamera, !bounds.size.equalTo(.zero) {
            store.bootstrapCameraIfNeeded(center: CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.5))
            hasBootstrappedCamera = true
        }

        updateWorldViewTransform()
        syncElementViews()
        handlePendingTerminalFocusRequest()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let store else {
            return
        }

        let background = NSRect(origin: .zero, size: bounds.size)
        theme.canvasBackground.setFill()
        background.fill()

        drawGrid(camera: store.camera, in: dirtyRect)

        if let previewWorldRect {
            let style = previewStyle ?? .selection
            let previewRect = worldView.convert(previewWorldRect, to: self)
            let previewPath = NSBezierPath(
                roundedRect: previewRect,
                xRadius: style.cornerRadius,
                yRadius: style.cornerRadius
            )
            style.fillColor.setFill()
            previewPath.fill()

            previewPath.lineWidth = 2
            previewPath.setLineDash(style.dashPattern, count: style.dashPattern.count, phase: 0)
            style.strokeColor.setStroke()
            previewPath.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let store else {
            return
        }

        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)

        if spacebarIsDown {
            interaction = .panning(anchor: location, initialPan: store.camera.pan)
            return
        }

        switch store.tool {
        case .select:
            interaction = .marqueeSelecting(
                startScreen: location,
                currentScreen: location,
                appendToSelection: event.modifierFlags.contains(.shift)
            )
            previewWorldRect = normalizedWorldRect(from: location, to: location)
            previewStyle = .selection
            needsDisplay = true
        case .terminal:
            interaction = .creatingTerminal(startScreen: location, currentScreen: location)
            previewWorldRect = normalizedWorldRect(from: location, to: location)
            previewStyle = .terminalCreation
            needsDisplay = true
        case .frame:
            interaction = .creatingFrame(startScreen: location, currentScreen: location)
            previewWorldRect = normalizedWorldRect(from: location, to: location)
            previewStyle = .frameCreation
            needsDisplay = true
        case .text:
            _ = store.createText(at: worldPoint(fromScreenPoint: location))
            store.tool = .select
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let store, let interaction else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)

        switch interaction {
        case let .panning(anchor, initialPan):
            let delta = CGPoint(x: location.x - anchor.x, y: location.y - anchor.y)
            store.setPan(CGPoint(x: initialPan.x + delta.x, y: initialPan.y + delta.y))
            updateWorldViewTransform()
        case let .creatingTerminal(startScreen, _):
            self.interaction = .creatingTerminal(startScreen: startScreen, currentScreen: location)
            previewWorldRect = normalizedWorldRect(from: startScreen, to: location)
        case let .creatingFrame(startScreen, _):
            self.interaction = .creatingFrame(startScreen: startScreen, currentScreen: location)
            previewWorldRect = normalizedWorldRect(from: startScreen, to: location)
        case let .marqueeSelecting(startScreen, _, appendToSelection):
            self.interaction = .marqueeSelecting(
                startScreen: startScreen,
                currentScreen: location,
                appendToSelection: appendToSelection
            )
            previewWorldRect = normalizedWorldRect(from: startScreen, to: location)
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let store else {
            interaction = nil
            previewWorldRect = nil
            previewStyle = nil
            needsDisplay = true
            return
        }

        defer {
            interaction = nil
            previewWorldRect = nil
            previewStyle = nil
            needsDisplay = true
        }

        guard let interaction else {
            return
        }

        switch interaction {
        case .panning:
            return
        case let .creatingTerminal(startScreen, currentScreen):
            var frame = normalizedWorldRect(from: startScreen, to: currentScreen)

            if frame.width < 24 || frame.height < 24 {
                let worldPoint = worldPoint(fromScreenPoint: currentScreen)
                frame = CGRect(
                    x: worldPoint.x - CanvasGeometry.defaultNodeSize.width * 0.5,
                    y: worldPoint.y - CanvasGeometry.defaultNodeSize.height * 0.5,
                    width: CanvasGeometry.defaultNodeSize.width,
                    height: CanvasGeometry.defaultNodeSize.height
                )
            }

            _ = store.createTerminal(frame: frame)
            store.tool = .select
        case let .creatingFrame(startScreen, currentScreen):
            var frame = normalizedWorldRect(from: startScreen, to: currentScreen)

            if frame.width < 24 || frame.height < 24 {
                let worldPoint = worldPoint(fromScreenPoint: currentScreen)
                frame = CGRect(
                    x: worldPoint.x - CanvasGeometry.defaultFrameSize.width * 0.5,
                    y: worldPoint.y - CanvasGeometry.defaultFrameSize.height * 0.5,
                    width: CanvasGeometry.defaultFrameSize.width,
                    height: CanvasGeometry.defaultFrameSize.height
                )
            }

            _ = store.createFrame(frame: frame)
            store.tool = .select
        case let .marqueeSelecting(startScreen, currentScreen, appendToSelection):
            let selectionRect = normalizedWorldRect(from: startScreen, to: currentScreen)
            let isClick = selectionRect.width < 8 && selectionRect.height < 8

            if isClick {
                if !appendToSelection {
                    store.clearSelection()
                }
            } else {
                store.selectElements(intersecting: selectionRect, append: appendToSelection)
            }
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let store else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        interaction = .panning(anchor: location, initialPan: store.camera.pan)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let store else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let gestureDelta = CanvasInputMapping.normalizedGestureDelta(
            scrollingDelta: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY),
            directionInvertedFromDevice: event.isDirectionInvertedFromDevice
        )

        if event.modifierFlags.contains(.command) {
            let factor = CanvasInputMapping.zoomFactor(for: gestureDelta.y)
            store.zoom(by: factor, around: location)
        } else {
            store.panBy(CanvasInputMapping.panDelta(for: gestureDelta))
        }

        updateWorldViewTransform()
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard let store else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        store.zoom(by: 1 + event.magnification, around: location)
        updateWorldViewTransform()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard let store else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 49 {
            spacebarIsDown = true
            return
        }

        if modifiers.contains(.command), let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case "a":
                store.selectAllElements()
                return
            case "d":
                store.duplicateSelection()
                return
            case "0":
                store.resetZoom()
                return
            case "+", "=":
                store.zoom(by: 1.12, around: CGPoint(x: bounds.midX, y: bounds.midY))
                return
            case "-", "_":
                store.zoom(by: 1 / 1.12, around: CGPoint(x: bounds.midX, y: bounds.midY))
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 53:
            store.clearSelection()
            store.tool = .select
            return
        case 48:
            store.cycleSelection(backward: modifiers.contains(.shift))
            return
        case 51, 117:
            store.deleteSelection()
            return
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "t":
            store.tool = .terminal
        case "f":
            store.tool = .frame
        case "x":
            store.tool = .text
        case "v", "s":
            store.tool = .select
        case "+", "=":
            store.zoom(by: 1.12, around: CGPoint(x: bounds.midX, y: bounds.midY))
        case "-", "_":
            store.zoom(by: 1 / 1.12, around: CGPoint(x: bounds.midX, y: bounds.midY))
        case "0":
            store.resetZoom()
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spacebarIsDown = false
            return
        }

        super.keyUp(with: event)
    }

    private func syncElementViews() {
        syncFrameViews()
        syncNodeViews()
        syncTextViews()
        syncWorldSubviewOrder()
    }

    private func syncFrameViews() {
        guard let store else {
            return
        }

        let desiredIDs = Set(store.frameItems.map(\.id))

        for (id, view) in frameViews where !desiredIDs.contains(id) {
            view.removeFromSuperview()
            frameViews[id] = nil
        }

        for (index, frameItem) in store.frameItems.enumerated() {
            let view: CanvasFrameItemView

            if let existing = frameViews[frameItem.id] {
                view = existing
            } else {
                let created = CanvasFrameItemView(title: frameItem.title)
                created.onActivate = { [weak self] extendSelection in
                    self?.store?.activateElement(frameItem.id, extendSelection: extendSelection)
                    self?.window?.makeFirstResponder(self)
                }
                created.onMove = { [weak self] delta in
                    self?.store?.moveSelection(anchorID: frameItem.id, byScreenDelta: delta) ?? .none
                }
                created.onResize = { [weak self] handle, delta in
                    self?.store?.resizeFrame(id: frameItem.id, handle: handle, byScreenDelta: delta) ?? .none
                }
                created.onTitleCommit = { [weak self] title in
                    self?.store?.renameFrame(id: frameItem.id, title: title)
                }
                worldView.addSubview(created)
                frameViews[frameItem.id] = created
                view = created
            }

            view.title = frameItem.title
            view.theme = theme
            view.isSelected = store.selectedElementIDs.contains(frameItem.id)
            view.isInteractionEnabled = store.tool == .select
            view.layer?.zPosition = LayerDepth.frameBase + CGFloat(index) + (view.isSelected ? LayerDepth.selectedBoost : 0)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = frameItem.frame
            CATransaction.commit()
        }
    }

    private func syncNodeViews() {
        guard let store else {
            return
        }

        let desiredIDs = Set(store.nodes.map(\.id))

        for (id, view) in nodeViews where !desiredIDs.contains(id) {
            view.removeFromSuperview()
            nodeViews[id] = nil
        }

        for (index, node) in store.nodes.enumerated() {
            let view: TerminalNodeView

            if let existing = nodeViews[node.id] {
                view = existing
            } else {
                let created = TerminalNodeView(
                    title: node.title,
                    initialTranscript: appModel?.restoredTranscript(for: node.id)
                )
                created.onMove = { [weak self] delta in
                    self?.store?.moveSelection(anchorID: node.id, byScreenDelta: delta) ?? .none
                }
                created.onResize = { [weak self] handle, delta in
                    self?.store?.resizeNode(id: node.id, handle: handle, byScreenDelta: delta) ?? .none
                }
                created.onClose = { [weak self] in
                    self?.store?.removeNode(id: node.id)
                }
                created.onChromeActivation = { [weak self] extendSelection in
                    self?.store?.activateElement(node.id, extendSelection: extendSelection)
                    self?.window?.makeFirstResponder(self)
                }
                created.onTerminalActivation = { [weak self, weak created] extendSelection in
                    self?.store?.activateElement(node.id, extendSelection: extendSelection)
                    if extendSelection {
                        self?.window?.makeFirstResponder(self)
                    } else {
                        created?.focusTerminal()
                    }
                }
                created.onTitleCommit = { [weak self] title in
                    self?.store?.renameNode(id: node.id, title: title)
                }
                created.onSessionOutput = { [weak self] data in
                    self?.appModel?.recordTerminalOutput(data, for: node.id)
                }
                created.onSessionInput = { [weak self] data in
                    self?.broadcastTerminalInput(data, fromNodeID: node.id)
                }
                worldView.addSubview(created)
                nodeViews[node.id] = created
                view = created
            }

            view.title = node.title
            view.theme = theme
            view.isSelected = store.selectedElementIDs.contains(node.id)
            view.layer?.zPosition = LayerDepth.nodeBase + CGFloat(index) + (view.isSelected ? LayerDepth.selectedBoost : 0)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = node.frame
            CATransaction.commit()
        }
    }

    private func broadcastTerminalInput(_ data: Data, fromNodeID originID: UUID) {
        guard
            let store,
            !data.isEmpty
        else {
            return
        }

        for targetID in store.terminalBroadcastTargetIDs(forOriginID: originID) {
            nodeViews[targetID]?.sendInput(data)
        }
    }

    private func syncTextViews() {
        guard let store else {
            return
        }

        let desiredIDs = Set(store.textItems.map(\.id))

        for (id, view) in textViews where !desiredIDs.contains(id) {
            view.removeFromSuperview()
            textViews[id] = nil
        }

        for (index, item) in store.textItems.enumerated() {
            let view: CanvasTextItemView

            if let existing = textViews[item.id] {
                view = existing
            } else {
                let created = CanvasTextItemView(text: item.text)
                created.onActivate = { [weak self] extendSelection in
                    self?.store?.activateElement(item.id, extendSelection: extendSelection)
                    self?.window?.makeFirstResponder(self)
                }
                created.onMove = { [weak self] delta in
                    self?.store?.moveSelection(anchorID: item.id, byScreenDelta: delta) ?? .none
                }
                created.onResize = { [weak self] handle, delta in
                    self?.store?.resizeTextItem(id: item.id, handle: handle, byScreenDelta: delta) ?? .none
                }
                created.onTextChange = { [weak self] text in
                    self?.store?.updateTextDraft(id: item.id, content: text)
                }
                created.onTextCommit = { [weak self] text in
                    self?.store?.commitText(id: item.id, content: text)
                }
                worldView.addSubview(created)
                textViews[item.id] = created
                view = created
            }

            view.text = item.text
            view.wrapWidth = item.wrapWidth
            view.theme = theme
            view.isSelected = store.selectedElementIDs.contains(item.id)
            view.layer?.zPosition = LayerDepth.textBase + CGFloat(index) + (view.isSelected ? LayerDepth.selectedBoost : 0)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = item.frame
            CATransaction.commit()

            if store.pendingTextEditID == item.id {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else {
                        return
                    }

                    self.store?.acknowledgePendingTextEdit(id: item.id)
                    view.beginEditing()
                }
            }
        }
    }

    private func handlePendingTerminalFocusRequest() {
        guard
            let store,
            let terminalID = store.pendingTerminalFocusID,
            let nodeView = nodeViews[terminalID]
        else {
            return
        }

        DispatchQueue.main.async { [weak self, weak nodeView] in
            guard
                let self,
                let store = self.store,
                let nodeView,
                store.pendingTerminalFocusID == terminalID
            else {
                return
            }

            store.acknowledgePendingTerminalFocus(id: terminalID)
            store.activateElement(terminalID)
            nodeView.focusTerminal()
        }
    }

    private func syncWorldSubviewOrder() {
        guard let store else {
            return
        }

        let desiredOrder =
            store.frameItems.compactMap { frameViews[$0.id] } +
            store.nodes.compactMap { nodeViews[$0.id] } +
            store.textItems.compactMap { textViews[$0.id] }

        let isAlreadyOrdered =
            worldView.subviews.count == desiredOrder.count &&
            zip(worldView.subviews, desiredOrder).allSatisfy { $0 === $1 }

        guard !isAlreadyOrdered else {
            return
        }

        var orderByViewID: [ObjectIdentifier: Int] = [:]
        for (index, view) in desiredOrder.enumerated() {
            orderByViewID[ObjectIdentifier(view)] = index
        }

        withUnsafeMutablePointer(to: &orderByViewID) { pointer in
            worldView.sortSubviews({ lhs, rhs, context in
                guard let context else {
                    return .orderedSame
                }

                let orderMap = context.assumingMemoryBound(to: [ObjectIdentifier: Int].self).pointee
                let leftIndex = orderMap[ObjectIdentifier(lhs)] ?? 0
                let rightIndex = orderMap[ObjectIdentifier(rhs)] ?? 0

                if leftIndex == rightIndex {
                    return .orderedSame
                }

                return leftIndex < rightIndex ? .orderedAscending : .orderedDescending
            }, context: UnsafeMutableRawPointer(pointer))
        }
    }

    private func drawGrid(camera: CanvasCamera, in dirtyRect: NSRect) {
        let step = CanvasGeometry.adaptiveGridStep(for: camera)
        let majorStep = step * 4
        let visibleMinWorld = worldView.bounds.origin
        let visibleMaxWorld = CGPoint(x: worldView.bounds.maxX, y: worldView.bounds.maxY)

        drawGridLines(
            from: visibleMinWorld,
            to: visibleMaxWorld,
            step: step,
            lineWidth: 1,
            color: theme.gridMinor,
            camera: camera
        )
        drawGridLines(
            from: visibleMinWorld,
            to: visibleMaxWorld,
            step: majorStep,
            lineWidth: 1.2,
            color: theme.gridMajor,
            camera: camera
        )
    }

    private func drawGridLines(from minWorld: CGPoint, to maxWorld: CGPoint, step: CGFloat, lineWidth: CGFloat, color: NSColor, camera: CanvasCamera) {
        guard step > 0 else {
            return
        }

        let path = NSBezierPath()
        path.lineWidth = lineWidth

        let startX = floor(minWorld.x / step) * step
        let endX = ceil(maxWorld.x / step) * step
        var x = startX
        while x <= endX {
            let screenX = x * camera.zoom + camera.pan.x
            path.move(to: CGPoint(x: screenX, y: 0))
            path.line(to: CGPoint(x: screenX, y: bounds.height))
            x += step
        }

        let startY = floor(minWorld.y / step) * step
        let endY = ceil(maxWorld.y / step) * step
        var y = startY
        while y <= endY {
            let screenY = y * camera.zoom + camera.pan.y
            path.move(to: CGPoint(x: 0, y: screenY))
            path.line(to: CGPoint(x: bounds.width, y: screenY))
            y += step
        }

        color.setStroke()
        path.stroke()
    }

    private func updateWorldViewTransform() {
        guard let store, !bounds.size.equalTo(.zero) else {
            return
        }

        worldView.frame = bounds
        worldView.bounds = CGRect(
            origin: CGPoint(
                x: -store.camera.pan.x / store.camera.zoom,
                y: -store.camera.pan.y / store.camera.zoom
            ),
            size: CGSize(
                width: bounds.width / store.camera.zoom,
                height: bounds.height / store.camera.zoom
            )
        )
    }

    private func worldPoint(fromScreenPoint point: CGPoint) -> CGPoint {
        worldView.convert(point, from: self)
    }

    private func normalizedWorldRect(from startScreen: CGPoint, to endScreen: CGPoint) -> CGRect {
        let startWorld = worldPoint(fromScreenPoint: startScreen)
        let endWorld = worldPoint(fromScreenPoint: endScreen)

        return CGRect(
            x: min(startWorld.x, endWorld.x),
            y: min(startWorld.y, endWorld.y),
            width: abs(endWorld.x - startWorld.x),
            height: abs(endWorld.y - startWorld.y)
        )
    }

    private func updateThemeIfNeeded() {
        let resolvedTheme = FloatermTheme(mode: appearanceMode, effectiveAppearance: effectiveAppearance)
        guard resolvedTheme != theme else {
            return
        }

        theme = resolvedTheme
        applyThemeToElementViews()
        needsDisplay = true
    }

    private func applyThemeToElementViews() {
        for view in frameViews.values {
            view.theme = theme
        }
        for view in nodeViews.values {
            view.theme = theme
        }
        for view in textViews.values {
            view.theme = theme
        }
    }
}

final class CanvasFrameItemView: NSView {
    var onActivate: ((Bool) -> Void)?
    var onMove: ((CGPoint) -> CanvasSnapState)?
    var onResize: ((ResizeHandle, CGPoint) -> CanvasSnapState)?
    var onTitleCommit: ((String) -> Void)?

    var title = "" {
        didSet {
            titleLabel.stringValue = title
            titleEditor.stringValue = title
            needsLayout = true
        }
    }

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    var isInteractionEnabled = true {
        didSet {
            guard isInteractionEnabled != oldValue else {
                return
            }

            window?.invalidateCursorRects(for: self)
        }
    }

    var theme = FloatermTheme(appearance: .dark) {
        didSet {
            guard theme != oldValue else {
                return
            }

            updateAppearance()
        }
    }

    private enum Interaction {
        case drag
    }

    private let frameCornerRadius: CGFloat = 16
    private let selectionOutlineInset: CGFloat = 4
    private let badgeInset: CGFloat = 14
    private let badgeHeight: CGFloat = 24
    private let badgeHorizontalPadding: CGFloat = 10
    private let titleButtonGap: CGFloat = 7
    private let titleButtonSize: CGFloat = 12
    private let edgeHandleThickness: CGFloat = 6
    private let cornerHandleSize: CGFloat = 14

    private let borderView = TerminalOutlineView()
    private let selectionOutlineView = DashedSelectionOutlineView()
    private let titleBadgeView = TerminalOutlineView()
    private let titleLabel = PassiveLabelTextField(labelWithString: "")
    private let titleEditor = InlineTitleEditorView()
    private let editTitleButton = IconClickView()
    private let snapFeedbackTracker = SnapFeedbackTracker()
    private var interaction: Interaction?
    private var editActionRect: CGRect = .zero

    private lazy var handles: [ResizeHandle: ResizeHandleView] = ResizeHandle.allCases.reduce(into: [:]) { result, handle in
        let view = ResizeHandleView(handle: handle)
        view.onActivate = { [weak self] in
            self?.onActivate?(false)
        }
        view.onDrag = { [weak self] dragHandle, delta in
            self?.onResize?(dragHandle, delta) ?? .none
        }
        result[handle] = view
    }

    override var acceptsFirstResponder: Bool { true }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title

        wantsLayer = true
        layer?.masksToBounds = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        titleLabel.alignment = .left
        titleLabel.cell?.lineBreakMode = .byClipping
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.isSelectable = false
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false

        titleEditor.stringValue = title
        titleEditor.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleEditor.alignment = .left
        titleEditor.textColor = NSColor(calibratedWhite: 0.82, alpha: 1)
        titleEditor.maximumCharacterCount = 40
        titleEditor.isHidden = true
        titleEditor.onChange = { [weak self] _ in
            self?.needsLayout = true
        }
        titleEditor.onCommit = { [weak self] title in
            self?.finishTitleEditing(with: title)
        }

        editTitleButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename frame")
        editTitleButton.toolTip = "Rename frame"
        editTitleButton.symbolPointSize = 9
        editTitleButton.symbolWeight = .medium

        addSubview(borderView)
        addSubview(selectionOutlineView)
        addSubview(titleBadgeView)
        addSubview(titleLabel)
        addSubview(titleEditor)
        addSubview(editTitleButton)

        for handleView in handles.values {
            addSubview(handleView)
        }

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        borderView.frame = bounds
        selectionOutlineView.frame = bounds.insetBy(dx: -selectionOutlineInset, dy: -selectionOutlineInset)
        selectionOutlineView.cornerRadius = frameCornerRadius + selectionOutlineInset

        let titleNaturalWidth = measuredTitleWidth()
        let badgeWidth = min(
            max(110, titleNaturalWidth + badgeHorizontalPadding * 2 + titleButtonSize + titleButtonGap),
            max(bounds.width - badgeInset * 2, 110)
        )
        let badgeFrame = CGRect(
            x: badgeInset,
            y: max(bounds.maxY - badgeInset - badgeHeight, bounds.minY + 10),
            width: badgeWidth,
            height: badgeHeight
        )
        titleBadgeView.frame = badgeFrame

        let labelHeight = ceil(max(titleLabel.intrinsicContentSize.height, titleEditor.intrinsicContentSize.height))
        let labelMaxWidth = max(badgeFrame.width - badgeHorizontalPadding * 2 - titleButtonSize - titleButtonGap, 40)
        let labelWidth = min(max(titleNaturalWidth, 40), labelMaxWidth)
        let titleFrame = CGRect(
            x: badgeFrame.minX + badgeHorizontalPadding,
            y: floor(badgeFrame.midY - labelHeight * 0.5),
            width: labelWidth,
            height: labelHeight
        )
        titleLabel.frame = titleFrame
        titleEditor.frame = titleFrame
        editTitleButton.frame = CGRect(
            x: titleFrame.maxX + titleButtonGap,
            y: floor(badgeFrame.midY - titleButtonSize * 0.5),
            width: titleButtonSize,
            height: titleButtonSize
        )
        editActionRect = editTitleButton.frame.insetBy(dx: -5, dy: -5)

        layoutResizeHandles()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        guard isInteractionEnabled else {
            return
        }

        let editRect = editTitleButton.isHidden ? .zero : editActionRect.intersection(bounds)
        let editingRect = titleEditor.isHidden ? .zero : titleEditor.frame.insetBy(dx: -2, dy: -2).intersection(bounds)
        let exclusions = [editRect, editingRect]
            .filter { !$0.isEmpty }
            .sorted { $0.minX < $1.minX }

        guard !exclusions.isEmpty else {
            addCursorRect(bounds, cursor: .openHand)
            return
        }

        var currentX: CGFloat = 0
        for exclusion in exclusions {
            let leftWidth = max(exclusion.minX - currentX, 0)
            if leftWidth > 0 {
                addCursorRect(
                    CGRect(x: currentX, y: 0, width: leftWidth, height: bounds.height),
                    cursor: .openHand
                )
            }
            currentX = max(currentX, exclusion.maxX)
        }

        if currentX < bounds.width {
            addCursorRect(
                CGRect(x: currentX, y: 0, width: bounds.width - currentX, height: bounds.height),
                cursor: .openHand
            )
        }

        if !editRect.isEmpty {
            addCursorRect(editRect, cursor: .pointingHand)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractionEnabled else {
            return nil
        }

        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if !editTitleButton.isHidden, editActionRect.contains(point) {
            beginTitleEditing()
            return
        }

        interaction = .drag
        snapFeedbackTracker.reset()
        onActivate?(event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        guard case .drag = interaction else {
            return
        }

        let snapState = onMove?(CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
        snapFeedbackTracker.update(with: snapState)
    }

    override func mouseUp(with event: NSEvent) {
        interaction = nil
        snapFeedbackTracker.reset()
    }

    private func updateAppearance() {
        let borderColor = isSelected ? theme.frameSelectedBorder : theme.frameBorder
        let fillColor = isSelected ? theme.frameSelectedFill : theme.frameFill
        let badgeFillColor = theme.frameBadgeFill
        let badgeBorderColor = isSelected ? theme.frameBadgeSelectedBorder : theme.frameBadgeBorder
        let titleColor = isSelected ? theme.frameTitleSelectedText : theme.frameTitleText
        let editButtonColor = isSelected ? theme.frameEditButtonSelected : theme.frameEditButton

        selectionOutlineView.isHidden = !isSelected
        selectionOutlineView.strokeColor = theme.selectionOutline
        titleLabel.textColor = titleColor
        titleEditor.textColor = titleColor
        editTitleButton.contentTintColor = editButtonColor
        editTitleButton.isHidden = !isSelected && titleEditor.isHidden

        borderView.apply(
            cornerRadius: frameCornerRadius,
            borderWidth: 1.25,
            borderColor: borderColor,
            backgroundColor: fillColor,
            shadowOpacity: isSelected ? 0.12 : 0.08,
            shadowRadius: isSelected ? 12 : 7
        )
        titleBadgeView.apply(
            cornerRadius: badgeHeight * 0.5,
            borderWidth: 1,
            borderColor: badgeBorderColor,
            backgroundColor: badgeFillColor,
            shadowOpacity: 0,
            shadowRadius: 0
        )

        for handleView in handles.values {
            handleView.isHidden = !isSelected
        }

        window?.invalidateCursorRects(for: self)
    }

    private func beginTitleEditing() {
        onActivate?(false)
        titleEditor.stringValue = title
        titleLabel.isHidden = true
        titleEditor.isHidden = false
        editTitleButton.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.titleEditor.beginEditing()
        }
    }

    private func finishTitleEditing(with proposedTitle: String) {
        let normalized = String(proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        titleLabel.isHidden = false
        titleEditor.isHidden = true

        if !normalized.isEmpty {
            title = normalized
            onTitleCommit?(normalized)
        } else {
            titleEditor.stringValue = title
        }

        needsLayout = true
        updateAppearance()
    }

    private func measuredTitleWidth() -> CGFloat {
        let visibleTitle = titleEditor.isHidden ? title : titleEditor.stringValue
        let text = visibleTitle.isEmpty ? " " : visibleTitle
        let font = titleLabel.font ?? .systemFont(ofSize: 12.5, weight: .semibold)
        let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return max(42, measuredWidth)
    }

    private func layoutResizeHandles() {
        handles[.topLeft]?.frame = CGRect(x: 0, y: bounds.height - cornerHandleSize, width: cornerHandleSize, height: cornerHandleSize)
        handles[.top]?.frame = CGRect(x: cornerHandleSize, y: bounds.height - edgeHandleThickness, width: bounds.width - cornerHandleSize * 2, height: edgeHandleThickness)
        handles[.topRight]?.frame = CGRect(x: bounds.width - cornerHandleSize, y: bounds.height - cornerHandleSize, width: cornerHandleSize, height: cornerHandleSize)
        handles[.right]?.frame = CGRect(x: bounds.width - edgeHandleThickness, y: cornerHandleSize, width: edgeHandleThickness, height: bounds.height - cornerHandleSize * 2)
        handles[.bottomRight]?.frame = CGRect(x: bounds.width - cornerHandleSize, y: 0, width: cornerHandleSize, height: cornerHandleSize)
        handles[.bottom]?.frame = CGRect(x: cornerHandleSize, y: 0, width: bounds.width - cornerHandleSize * 2, height: edgeHandleThickness)
        handles[.bottomLeft]?.frame = CGRect(x: 0, y: 0, width: cornerHandleSize, height: cornerHandleSize)
        handles[.left]?.frame = CGRect(x: 0, y: cornerHandleSize, width: edgeHandleThickness, height: bounds.height - cornerHandleSize * 2)
    }
}

final class TerminalNodeView: NSView {
    var onMove: ((CGPoint) -> CanvasSnapState)?
    var onResize: ((ResizeHandle, CGPoint) -> CanvasSnapState)?
    var onClose: (() -> Void)?
    var onChromeActivation: ((Bool) -> Void)?
    var onTerminalActivation: ((Bool) -> Void)?
    var onTitleCommit: ((String) -> Void)?
    var onSessionOutput: ((Data) -> Void)?
    var onSessionInput: ((Data) -> Void)?

    var title = "" {
        didSet {
            titleLabel.stringValue = title
            titleEditor.stringValue = title
            needsLayout = true
        }
    }

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    var theme = FloatermTheme(appearance: .dark) {
        didSet {
            guard theme != oldValue else {
                return
            }

            terminalView.appearanceTheme = theme.appearance
            updateAppearance()
        }
    }

    private let shellInset: CGFloat = 4
    private let shellCornerRadius: CGFloat = 10
    private let selectionOutlineInset: CGFloat = 3
    private let titlebarInset: CGFloat = 1
    private let titlebarHeight: CGFloat = 24
    private let titleAfterCloseGap: CGFloat = 14
    private let titleTrailingInset: CGFloat = 14
    private let titleButtonGap: CGFloat = 8
    private let titleButtonSize: CGFloat = 12
    private let contentHorizontalInset: CGFloat = 1
    private let contentBottomInset: CGFloat = 1
    private let contentTopGap: CGFloat = 1
    private let closeButtonLeadingInset: CGFloat = 12
    private let closeButtonSize: CGFloat = 10
    private let chromeLineWidth: CGFloat = 1
    private let separatorHeight: CGFloat = 1
    private let edgeHandleThickness: CGFloat = 6
    private let cornerHandleSize: CGFloat = 14

    private let shellView = TerminalOutlineView()
    private let selectionOutlineView = DashedSelectionOutlineView()
    private let titlebarView = TerminalOutlineView()
    private let titlebarSeparatorView = TerminalOutlineView()
    private let terminalFrameView = TerminalOutlineView()
    private let dragStripView = DragHeaderView()
    private let titleLabel = PassiveLabelTextField(labelWithString: "")
    private let titleEditor = InlineTitleEditorView()
    private let closeButton = CursorButton()
    private let editTitleButton = IconClickView()
    private let terminalView: TerminalWebView
    private var contentBottomCornerRadius: CGFloat {
        max(shellCornerRadius - shellInset, 0)
    }
    private lazy var handles: [ResizeHandle: ResizeHandleView] = ResizeHandle.allCases.reduce(into: [:]) { result, handle in
        let view = ResizeHandleView(handle: handle)
        view.onActivate = { [weak self] in
            self?.onChromeActivation?(false)
        }
        view.onDrag = { [weak self] dragHandle, delta in
            self?.onResize?(dragHandle, delta) ?? .none
        }
        result[handle] = view
    }

    init(title: String, initialTranscript: Data? = nil) {
        terminalView = TerminalWebView(initialTranscript: initialTranscript)
        super.init(frame: .zero)
        self.title = title

        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.textColor = NSColor(calibratedWhite: 0.74, alpha: 1)
        titleLabel.cell?.lineBreakMode = .byClipping
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.isSelectable = false
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false

        titleEditor.stringValue = title
        titleEditor.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleEditor.alignment = .center
        titleEditor.textColor = NSColor(calibratedWhite: 0.74, alpha: 1)
        titleEditor.maximumCharacterCount = 20
        titleEditor.isHidden = true
        titleEditor.onChange = { [weak self] _ in
            self?.needsLayout = true
        }
        titleEditor.onCommit = { [weak self] title in
            self?.finishTitleEditing(with: title)
        }

        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close terminal")
        closeButton.contentTintColor = NSColor(calibratedRed: 0.34, green: 0.12, blue: 0.11, alpha: 1)
        closeButton.bezelStyle = .regularSquare
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.toolTip = "Close terminal"
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.wantsLayer = true
        closeButton.layer?.masksToBounds = true
        if let image = closeButton.image {
            let configuration = NSImage.SymbolConfiguration(pointSize: 6, weight: .bold)
            closeButton.image = image.withSymbolConfiguration(configuration)
        }

        editTitleButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename terminal")
        editTitleButton.toolTip = "Rename terminal"
        editTitleButton.symbolPointSize = 9
        editTitleButton.symbolWeight = .medium

        dragStripView.onActivate = { [weak self] extendSelection in
            self?.onChromeActivation?(extendSelection)
        }
        dragStripView.onDrag = { [weak self] delta in
            self?.onMove?(delta) ?? .none
        }
        dragStripView.onEditTitle = { [weak self] in
            self?.beginTitleEditing()
        }
        dragStripView.onClose = { [weak self] in
            self?.onClose?()
        }

        terminalView.onActivate = { [weak self] extendSelection in
            self?.onTerminalActivation?(extendSelection)
        }
        terminalView.onOutput = { [weak self] data in
            self?.onSessionOutput?(data)
        }
        terminalView.onInput = { [weak self] data in
            self?.onSessionInput?(data)
        }

        addSubview(shellView)
        addSubview(selectionOutlineView)
        addSubview(titlebarView)
        addSubview(titlebarSeparatorView)
        addSubview(terminalFrameView)
        addSubview(terminalView)
        addSubview(dragStripView)

        for handleView in handles.values {
            addSubview(handleView)
        }

        addSubview(closeButton)
        addSubview(titleLabel)
        addSubview(titleEditor)
        addSubview(editTitleButton)

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let shellFrame = bounds.insetBy(dx: shellInset, dy: shellInset)
        let selectionOutlineFrame = shellFrame.insetBy(dx: -selectionOutlineInset, dy: -selectionOutlineInset)
        let titlebarFrame = CGRect(
            x: shellFrame.minX + titlebarInset,
            y: shellFrame.maxY - titlebarInset - titlebarHeight,
            width: shellFrame.width - (titlebarInset * 2),
            height: titlebarHeight
        )
        let separatorFrame = CGRect(
            x: titlebarFrame.minX,
            y: titlebarFrame.minY - separatorHeight,
            width: titlebarFrame.width,
            height: separatorHeight
        )
        let contentFrame = CGRect(
            x: shellFrame.minX + contentHorizontalInset,
            y: shellFrame.minY + contentBottomInset,
            width: shellFrame.width - (contentHorizontalInset * 2),
            height: max(separatorFrame.minY - shellFrame.minY - contentBottomInset - contentTopGap, 120)
        )

        shellView.frame = shellFrame
        selectionOutlineView.frame = selectionOutlineFrame
        selectionOutlineView.cornerRadius = shellCornerRadius + selectionOutlineInset
        titlebarView.frame = titlebarFrame
        titlebarSeparatorView.frame = separatorFrame
        dragStripView.frame = titlebarFrame
        closeButton.frame = CGRect(
            x: titlebarFrame.minX + closeButtonLeadingInset,
            y: floor(titlebarFrame.midY - (closeButtonSize * 0.5)),
            width: closeButtonSize,
            height: closeButtonSize
        )
        closeButton.layer?.cornerRadius = closeButtonSize * 0.5

        let titleClusterMinX = closeButton.frame.maxX + titleAfterCloseGap
        let titleClusterMaxX = titlebarFrame.maxX - titleTrailingInset
        let titleClusterAvailableWidth = max(titleClusterMaxX - titleClusterMinX, 40)
        let titleHeight = ceil(max(titleLabel.intrinsicContentSize.height, titleEditor.intrinsicContentSize.height))
        let titleNaturalWidth = measuredTitleWidth()
        let titleWidth = min(
            titleNaturalWidth,
            max(40, titleClusterAvailableWidth - titleButtonSize - titleButtonGap)
        )
        let centeredTitleX = floor(titlebarFrame.midX - (titleWidth * 0.5))
        let maxTitleX = max(titleClusterMinX, titleClusterMaxX - titleWidth - titleButtonGap - titleButtonSize)
        let titleX = min(max(centeredTitleX, titleClusterMinX), maxTitleX)
        let titleFrame = CGRect(
            x: titleX,
            y: floor(titlebarFrame.midY - (titleHeight * 0.5)),
            width: titleWidth,
            height: titleHeight
        )
        titleLabel.frame = titleFrame
        titleEditor.frame = titleFrame
        editTitleButton.frame = CGRect(
            x: titleFrame.maxX + titleButtonGap,
            y: floor(titlebarFrame.midY - (titleButtonSize * 0.5)),
            width: titleButtonSize,
            height: titleButtonSize
        )
        terminalView.frame = contentFrame
        terminalView.logicalSize = contentFrame.size
        terminalView.layer?.cornerRadius = contentBottomCornerRadius
        terminalView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        terminalFrameView.frame = contentFrame.insetBy(dx: -1, dy: -1)
        dragStripView.closeActionRect = dragStripView.convert(closeButton.frame, from: self).insetBy(dx: -6, dy: -6)
        dragStripView.editActionRect = dragStripView.convert(editTitleButton.frame, from: self).insetBy(dx: -4, dy: -4)
        dragStripView.cursorExclusionRects = titleEditor.isHidden
            ? []
            : [dragStripView.convert(titleEditor.frame, from: self).insetBy(dx: -2, dy: -2)]

        layoutResizeHandles()
        window?.invalidateCursorRects(for: self)
    }

    @objc
    private func handleClose() {
        onClose?()
    }

    func focusTerminal() {
        terminalView.focusTerminal()
    }

    func sendInput(_ data: Data) {
        terminalView.sendInput(data)
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.shadowOpacity = 0
        let shellBorderColor = isSelected ? theme.terminalSelectedShellBorder : theme.terminalShellBorder
        let shellFillColor = theme.terminalShellFill
        let selectionOutlineColor = theme.selectionOutline
        let titlebarFillColor = theme.terminalTitlebarFill
        let separatorColor = theme.terminalSeparator
        let contentBorderColor = isSelected ? theme.terminalSelectedContentBorder : theme.terminalContentBorder
        let titleColor = isSelected ? theme.terminalTitleSelectedText : theme.terminalTitleText
        let closeButtonFillColor = isSelected ? theme.terminalCloseSelectedFill : theme.terminalCloseFill
        let closeButtonGlyphColor = theme.terminalCloseGlyph
        let editButtonColor = isSelected ? theme.terminalEditButtonSelected : theme.terminalEditButton

        closeButton.isHidden = false
        closeButton.contentTintColor = closeButtonGlyphColor
        closeButton.layer?.backgroundColor = closeButtonFillColor.cgColor
        editTitleButton.contentTintColor = editButtonColor
        titleLabel.textColor = titleColor
        titleEditor.textColor = titleColor
        selectionOutlineView.strokeColor = selectionOutlineColor
        selectionOutlineView.isHidden = !isSelected

        shellView.apply(
            cornerRadius: shellCornerRadius,
            borderWidth: chromeLineWidth,
            borderColor: shellBorderColor,
            backgroundColor: shellFillColor,
            shadowOpacity: isSelected ? 0.20 : 0.12,
            shadowRadius: isSelected ? 12 : 8
        )
        titlebarView.apply(
            cornerRadius: max(shellCornerRadius - titlebarInset, 0),
            borderWidth: 0,
            borderColor: .clear,
            backgroundColor: titlebarFillColor,
            shadowOpacity: 0,
            shadowRadius: 0,
            maskedCorners: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner],
            masksToBounds: true
        )
        titlebarSeparatorView.apply(
            cornerRadius: 0,
            borderWidth: 0,
            borderColor: .clear,
            backgroundColor: separatorColor,
            shadowOpacity: 0,
            shadowRadius: 0
        )
        terminalFrameView.apply(
            cornerRadius: contentBottomCornerRadius,
            borderWidth: chromeLineWidth,
            borderColor: contentBorderColor,
            backgroundColor: .clear,
            shadowOpacity: 0,
            shadowRadius: 0,
            maskedCorners: [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        )
        dragStripView.applyStyle(
            cornerRadius: 0,
            borderWidth: 0,
            borderColor: .clear,
            backgroundColor: .clear
        )
        window?.invalidateCursorRects(for: self)
    }

    private func beginTitleEditing() {
        terminalView.suppressAutoFocus()
        titleEditor.stringValue = title
        titleLabel.isHidden = true
        titleEditor.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.titleEditor.beginEditing()
        }
    }

    private func finishTitleEditing(with proposedTitle: String) {
        let normalized = String(proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        titleLabel.isHidden = false
        titleEditor.isHidden = true

        if !normalized.isEmpty {
            title = normalized
            onTitleCommit?(normalized)
        } else {
            titleEditor.stringValue = title
        }

        needsLayout = true
    }

    private func measuredTitleWidth() -> CGFloat {
        let visibleTitle = titleEditor.isHidden ? title : titleEditor.stringValue
        let text = visibleTitle.isEmpty ? " " : visibleTitle
        let font = titleLabel.font ?? .systemFont(ofSize: 12.5, weight: .semibold)
        let measuredWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return max(40, measuredWidth + 8)
    }

    private func layoutResizeHandles() {
        handles[.topLeft]?.frame = CGRect(x: 0, y: bounds.height - cornerHandleSize, width: cornerHandleSize, height: cornerHandleSize)
        handles[.top]?.frame = CGRect(x: cornerHandleSize, y: bounds.height - edgeHandleThickness, width: bounds.width - (cornerHandleSize * 2), height: edgeHandleThickness)
        handles[.topRight]?.frame = CGRect(x: bounds.width - cornerHandleSize, y: bounds.height - cornerHandleSize, width: cornerHandleSize, height: cornerHandleSize)
        handles[.right]?.frame = CGRect(x: bounds.width - edgeHandleThickness, y: cornerHandleSize, width: edgeHandleThickness, height: bounds.height - (cornerHandleSize * 2))
        handles[.bottomRight]?.frame = CGRect(x: bounds.width - cornerHandleSize, y: 0, width: cornerHandleSize, height: cornerHandleSize)
        handles[.bottom]?.frame = CGRect(x: cornerHandleSize, y: 0, width: bounds.width - (cornerHandleSize * 2), height: edgeHandleThickness)
        handles[.bottomLeft]?.frame = CGRect(x: 0, y: 0, width: cornerHandleSize, height: cornerHandleSize)
        handles[.left]?.frame = CGRect(x: 0, y: cornerHandleSize, width: edgeHandleThickness, height: bounds.height - (cornerHandleSize * 2))
    }
}

final class CanvasTextItemView: NSView {
    var onActivate: ((Bool) -> Void)?
    var onMove: ((CGPoint) -> CanvasSnapState)?
    var onResize: ((ResizeHandle, CGPoint) -> CanvasSnapState)?
    var onTextChange: ((String) -> Void)?
    var onTextCommit: ((String) -> Void)?

    var text = "" {
        didSet {
            textView.text = text
        }
    }

    var wrapWidth: CGFloat? {
        didSet {
            textView.wrapWidth = wrapWidth.map { max($0, 1) }
            needsLayout = true
        }
    }

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    var theme = FloatermTheme(appearance: .dark) {
        didSet {
            guard theme != oldValue else {
                return
            }

            updateAppearance()
        }
    }

    private let textView = EditableCanvasTextView()
    private let horizontalPadding = CanvasGeometry.textPadding.width * 0.5
    private let verticalPadding = CanvasGeometry.textPadding.height * 0.5
    private let edgeHandleThickness: CGFloat = 10
    private let cornerHandleSize: CGFloat = 18
    private lazy var handles: [ResizeHandle: ResizeHandleView] = [ResizeHandle.left, .right].reduce(into: [ResizeHandle: ResizeHandleView]()) { result, handle in
        let view = ResizeHandleView(handle: handle)
        view.onActivate = { [weak self] in
            self?.onActivate?(false)
        }
        view.onDrag = { [weak self] handle, delta in
            self?.onResize?(handle, delta) ?? .none
        }
        result[handle] = view
    }

    init(text: String) {
        super.init(frame: .zero)
        self.text = text

        wantsLayer = true
        layer?.masksToBounds = false

        textView.text = text
        textView.wrapWidth = nil
        textView.onActivate = { [weak self] extendSelection in
            self?.onActivate?(extendSelection)
        }
        textView.onDrag = { [weak self] delta in
            self?.onMove?(delta) ?? .none
        }
        textView.onChange = { [weak self] value in
            self?.onTextChange?(value)
        }
        textView.onCommit = { [weak self] value in
            self?.onTextCommit?(value)
        }

        addSubview(textView)
        for handleView in handles.values {
            addSubview(handleView)
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        textView.frame = bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
        let verticalHandleHeight = max(bounds.height - (cornerHandleSize * 2), 0)
        handles[.left]?.frame = CGRect(x: 0, y: cornerHandleSize, width: edgeHandleThickness, height: verticalHandleHeight)
        handles[.right]?.frame = CGRect(x: bounds.width - edgeHandleThickness, y: cornerHandleSize, width: edgeHandleThickness, height: verticalHandleHeight)
    }

    func beginEditing() {
        onActivate?(false)
        textView.beginEditing()
    }

    private func updateAppearance() {
        let showSelection = isSelected && !textView.isEditing
        textView.foregroundColor = theme.canvasTextColor
        layer?.backgroundColor = showSelection ? NSColor.systemBlue.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
        layer?.borderColor = showSelection ? NSColor.systemBlue.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
        layer?.borderWidth = showSelection ? 1.25 : 0
        layer?.cornerRadius = 9
        for handleView in handles.values {
            handleView.isHidden = !showSelection
        }
    }
}

final class InlineTitleEditorView: NSView, NSTextViewDelegate {
    var onChange: ((String) -> Void)?
    var onCommit: ((String) -> Void)?

    var stringValue: String {
        get { textView.string }
        set {
            if textView.string != newValue {
                textView.string = newValue
                applyTextStyle()
                invalidateIntrinsicContentSize()
            }
        }
    }

    var font: NSFont? {
        didSet {
            textView.font = font
            applyTextStyle()
            invalidateIntrinsicContentSize()
        }
    }

    var alignment: NSTextAlignment = .center {
        didSet {
            applyTextStyle()
        }
    }

    var textColor: NSColor? {
        didSet {
            textView.textColor = textColor
            textView.insertionPointColor = textColor ?? .white
        }
    }

    var maximumCharacterCount: Int = 20

    var isEditing: Bool {
        window?.firstResponder === textView
    }

    private let textView = TitleEditingTextView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private var isApplyingCharacterLimit = false
    private var didCommitCurrentSession = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false

        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byClipping
        textView.onCommit = { [weak self] in
            self?.commitIfNeeded()
        }

        scrollView.documentView = textView
        addSubview(scrollView)
        applyTextStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.frame = bounds
        textView.textContainer?.containerSize = CGSize(width: max(bounds.width, 1), height: CGFloat.greatestFiniteMagnitude)
    }

    override var intrinsicContentSize: NSSize {
        let text = stringValue.isEmpty ? " " : stringValue
        let measuredFont = font ?? .systemFont(ofSize: 12.5, weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: measuredFont])
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    func beginEditing() {
        didCommitCurrentSession = false
        textView.isEditable = true
        textView.isSelectable = true
        guard let window else {
            return
        }

        let selectionRange = NSRange(location: 0, length: textView.string.utf16.count)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(selectionRange)

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !self.isEditing else {
                return
            }

            window.makeFirstResponder(self.textView)
            self.textView.setSelectedRange(selectionRange)
        }
    }

    func currentEditor() -> NSTextView? {
        isEditing ? textView : nil
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingCharacterLimit else {
            invalidateIntrinsicContentSize()
            onChange?(stringValue)
            return
        }

        if textView.string.count > maximumCharacterCount {
            isApplyingCharacterLimit = true
            textView.string = String(textView.string.prefix(maximumCharacterCount))
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            isApplyingCharacterLimit = false
        }

        applyTextStyle()
        invalidateIntrinsicContentSize()
        onChange?(stringValue)
    }

    private func commitIfNeeded() {
        guard !didCommitCurrentSession else {
            return
        }

        didCommitCurrentSession = true
        textView.isEditable = false
        textView.isSelectable = false
        onCommit?(textView.string)
    }

    private func applyTextStyle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byClipping

        textView.defaultParagraphStyle = paragraphStyle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: textColor ?? NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        textView.typingAttributes = attributes

        guard let storage = textView.textStorage else {
            return
        }

        let selectedRange = textView.selectedRange()
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        textView.setSelectedRange(selectedRange)
    }
}

final class TitleEditingTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertTab(_:)), #selector(cancelOperation(_:)):
            onCommit?()
        default:
            super.doCommand(by: selector)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            onCommit?()
        }
        return didResign
    }
}

final class EditableCanvasTextView: NSView, NSTextViewDelegate {
    var onActivate: ((Bool) -> Void)?
    var onDrag: ((CGPoint) -> CanvasSnapState)?
    var onChange: ((String) -> Void)?
    var onCommit: ((String) -> Void)?

    var text: String {
        get { textView.string }
        set {
            if textView.string != newValue {
                textView.string = newValue
            }
        }
    }

    var wrapWidth: CGFloat? {
        didSet {
            configureTextContainer()
        }
    }

    var isEditing: Bool {
        window?.firstResponder === textView
    }

    var foregroundColor: NSColor = .white {
        didSet {
            applyTextAppearance()
        }
    }

    private let textView: CanvasIntrinsicTextView
    private let scrollView: NSScrollView

    override init(frame frameRect: NSRect) {
        let textContainer = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        textView = CanvasIntrinsicTextView(frame: .zero, textContainer: textContainer)
        scrollView = NSScrollView(frame: .zero)

        super.init(frame: frameRect)

        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = .zero
        textView.font = CanvasGeometry.textFont
        textView.allowsUndo = true
        textView.isEditable = false
        textView.isSelectable = false
        textView.onActivate = { [weak self] extendSelection in
            self?.onActivate?(extendSelection)
        }
        textView.onDrag = { [weak self] delta in
            self?.onDrag?(delta) ?? .none
        }
        textView.onCommit = { [weak self] in
            self?.endEditing()
        }

        addSubview(scrollView)
        configureTextContainer()
        applyTextAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.frame = bounds
    }

    func beginEditing() {
        textView.isEditable = true
        textView.isSelectable = true
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    }

    func endEditing() {
        textView.isEditable = false
        textView.isSelectable = false
        onCommit?(textView.string)
    }

    func textDidChange(_ notification: Notification) {
        onChange?(textView.string)
    }

    private func configureTextContainer() {
        if let wrapWidth {
            textView.textContainer?.containerSize = CGSize(width: max(wrapWidth, 1), height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.maxSize = CGSize(width: max(wrapWidth, 1), height: CGFloat.greatestFiniteMagnitude)
        } else {
            textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = false
            textView.isHorizontallyResizable = true
            textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    private func applyTextAppearance() {
        textView.textColor = foregroundColor
        textView.insertionPointColor = foregroundColor
        var typingAttributes = textView.typingAttributes
        typingAttributes[.foregroundColor] = foregroundColor
        typingAttributes[.font] = CanvasGeometry.textFont
        textView.typingAttributes = typingAttributes

        guard let storage = textView.textStorage, storage.length > 0 else {
            return
        }

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: foregroundColor, range: NSRange(location: 0, length: storage.length))
        storage.addAttribute(.font, value: CanvasGeometry.textFont, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }
}

final class CanvasIntrinsicTextView: NSTextView {
    var onActivate: ((Bool) -> Void)?
    var onDrag: ((CGPoint) -> CanvasSnapState)?
    var onCommit: (() -> Void)?

    private let snapFeedbackTracker = SnapFeedbackTracker()

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder === self {
            super.mouseDown(with: event)
            return
        }

        onActivate?(event.modifierFlags.contains(.shift))
        snapFeedbackTracker.reset()

        if event.clickCount >= 2 {
            isEditable = true
            isSelectable = true
            window?.makeFirstResponder(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard window?.firstResponder !== self else {
            super.mouseDragged(with: event)
            return
        }

        let snapState = onDrag?(CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
        snapFeedbackTracker.update(with: snapState)
    }

    override func mouseUp(with event: NSEvent) {
        snapFeedbackTracker.reset()
        super.mouseUp(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCommit?()
            return
        }

        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        snapFeedbackTracker.reset()
        if didResign, isEditable || isSelectable {
            onCommit?()
        }
        return didResign
    }
}

final class PassiveLabelTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class TerminalOutlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func apply(
        cornerRadius: CGFloat,
        borderWidth: CGFloat,
        borderColor: NSColor,
        backgroundColor: NSColor,
        shadowOpacity: Float,
        shadowRadius: CGFloat,
        maskedCorners: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
        ],
        masksToBounds: Bool = false
    ) {
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = borderWidth
        layer?.borderColor = borderColor.cgColor
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.maskedCorners = maskedCorners
        layer?.masksToBounds = masksToBounds
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = shadowRadius
        layer?.shadowOpacity = shadowOpacity
    }
}

final class DashedSelectionOutlineView: NSView {
    var strokeColor: NSColor = .white {
        didSet {
            shapeLayer.strokeColor = strokeColor.cgColor
        }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            updatePath()
        }
    }

    private let shapeLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        shapeLayer.fillColor = NSColor.clear.cgColor
        shapeLayer.lineWidth = 1
        shapeLayer.lineDashPattern = [2, 4]
        shapeLayer.strokeColor = strokeColor.cgColor
        layer?.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        updatePath()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func updatePath() {
        let inset = shapeLayer.lineWidth * 0.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        shapeLayer.path = CGPath(
            roundedRect: rect,
            cornerWidth: max(cornerRadius - inset, 0),
            cornerHeight: max(cornerRadius - inset, 0),
            transform: nil
        )
    }
}

final class SnapFeedbackTracker {
    private var lastSnapState = CanvasSnapState.none

    func reset() {
        lastSnapState = .none
    }

    func update(with snapState: CanvasSnapState?) {
        let snapState = snapState ?? .none

        guard snapState.isActive else {
            lastSnapState = .none
            return
        }

        guard snapState != lastSnapState else {
            return
        }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        lastSnapState = snapState
    }
}

final class DragHeaderView: NSView {
    var onDrag: ((CGPoint) -> CanvasSnapState)?
    var onActivate: ((Bool) -> Void)?
    var onEditTitle: (() -> Void)?
    var onClose: (() -> Void)?
    var cursorExclusionRects: [CGRect] = []
    var editActionRect: CGRect = .zero
    var closeActionRect: CGRect = .zero

    private enum Interaction {
        case drag
        case close
    }

    private var interaction: Interaction?
    private let snapFeedbackTracker = SnapFeedbackTracker()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        let pointerRects = [closeActionRect, editActionRect]
            .map { $0.intersection(bounds) }
            .filter { !$0.isEmpty }

        let exclusions = (cursorExclusionRects + pointerRects)
            .map { $0.intersection(bounds) }
            .filter { !$0.isEmpty }
            .sorted { $0.minX < $1.minX }

        guard !exclusions.isEmpty else {
            addCursorRect(bounds, cursor: .openHand)
            return
        }

        var currentX: CGFloat = 0
        for exclusion in exclusions {
            let leftWidth = max(exclusion.minX - currentX, 0)
            if leftWidth > 0 {
                addCursorRect(
                    CGRect(x: currentX, y: 0, width: leftWidth, height: bounds.height),
                    cursor: .openHand
                )
            }
            currentX = max(currentX, exclusion.maxX)
        }

        if currentX < bounds.width {
            addCursorRect(
                CGRect(x: currentX, y: 0, width: bounds.width - currentX, height: bounds.height),
                cursor: .openHand
            )
        }

        for rect in pointerRects {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if closeActionRect.contains(point) {
            interaction = .close
            snapFeedbackTracker.reset()
            return
        }

        if editActionRect.contains(point) {
            interaction = nil
            snapFeedbackTracker.reset()
            onEditTitle?()
            return
        }

        interaction = .drag
        snapFeedbackTracker.reset()
        onActivate?(event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        guard case .drag = interaction else {
            return
        }

        let snapState = onDrag?(CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
        snapFeedbackTracker.update(with: snapState)
    }

    override func mouseUp(with event: NSEvent) {
        defer { interaction = nil }
        snapFeedbackTracker.reset()

        let point = convert(event.locationInWindow, from: nil)

        switch interaction {
        case .close where closeActionRect.contains(point):
            onClose?()
        default:
            break
        }
    }

    func applyStyle(cornerRadius: CGFloat, borderWidth: CGFloat, borderColor: NSColor, backgroundColor: NSColor) {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = borderWidth
        layer?.borderColor = borderColor.cgColor
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

final class CursorButton: NSButton {
    override var acceptsFirstResponder: Bool {
        false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class IconClickView: NSView {
    var image: NSImage? {
        didSet {
            updateImage()
        }
    }

    var contentTintColor: NSColor = .white {
        didSet {
            imageView.contentTintColor = contentTintColor
        }
    }

    var symbolPointSize: CGFloat = 9 {
        didSet {
            updateImage()
        }
    }

    var symbolWeight: NSFont.Weight = .regular {
        didSet {
            updateImage()
        }
    }

    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = contentTintColor
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func updateImage() {
        if let image {
            let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: symbolWeight)
            imageView.image = image.withSymbolConfiguration(configuration)
        } else {
            imageView.image = nil
        }
    }
}

final class ResizeHandleView: NSView {
    let handle: ResizeHandle
    var onDrag: ((ResizeHandle, CGPoint) -> CanvasSnapState)?
    var onActivate: (() -> Void)?

    private static let diagonalDescendingCursor = privateResizeCursor(named: "_windowResizeNorthWestSouthEastCursor")
    private static let diagonalAscendingCursor = privateResizeCursor(named: "_windowResizeNorthEastSouthWestCursor")
    private let snapFeedbackTracker = SnapFeedbackTracker()

    init(handle: ResizeHandle) {
        self.handle = handle
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        let cursor: NSCursor

        switch handle {
        case .left, .right:
            cursor = .resizeLeftRight
        case .top, .bottom:
            cursor = .resizeUpDown
        case .topLeft, .bottomRight:
            cursor = Self.diagonalDescendingCursor
        case .topRight, .bottomLeft:
            cursor = Self.diagonalAscendingCursor
        }

        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        snapFeedbackTracker.reset()
        onActivate?()
    }

    override func mouseDragged(with event: NSEvent) {
        let snapState = onDrag?(handle, CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
        snapFeedbackTracker.update(with: snapState)
    }

    override func mouseUp(with event: NSEvent) {
        snapFeedbackTracker.reset()
    }

    private static func privateResizeCursor(named selectorName: String) -> NSCursor {
        let selector = Selector(selectorName)
        guard
            NSCursor.responds(to: selector),
            let unmanaged = NSCursor.perform(selector),
            let cursor = unmanaged.takeUnretainedValue() as? NSCursor
        else {
            return .crosshair
        }

        return cursor
    }
}

final class TerminalWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    var onActivate: ((Bool) -> Void)?
    var onOutput: ((Data) -> Void)?
    var onInput: ((Data) -> Void)?

    var logicalSize: CGSize = .zero {
        didSet {
            guard oldValue != logicalSize else {
                return
            }

            fitToLogicalSizeIfNeeded()
        }
    }

    var appearanceTheme: FloatermResolvedAppearance = .dark {
        didSet {
            guard appearanceTheme != oldValue else {
                return
            }

            applyAppearanceTheme()
        }
    }

    private var session: TerminalSession?
    private var isReady = false
    private var bufferedChunks: [String] = []
    private var lastGridSize = TerminalGridSize(columns: 100, rows: 30)
    private var lastFittedLogicalSize: CGSize = .zero
    private let initialTranscript: Data?
    private var shouldAutoFocusOnReady = true

    init(initialTranscript: Data? = nil) {
        self.initialTranscript = initialTranscript
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()

        super.init(frame: .zero, configuration: configuration)

        controller.add(WeakScriptMessageHandler(delegate: self), name: "terminal")
        navigationDelegate = self
        setValue(false, forKey: "drawsBackground")
        underPageBackgroundColor = .black
        layer?.cornerRadius = 0
        layer?.masksToBounds = true

        loadFrontend()
        if let initialTranscript, !initialTranscript.isEmpty {
            appendOutput(initialTranscript, persist: false)
        }
        startSession()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        session?.close()
    }

    override func mouseDown(with event: NSEvent) {
        let extendSelection = event.modifierFlags.contains(.shift)
        onActivate?(extendSelection)
        if extendSelection {
            return
        }
        super.mouseDown(with: event)
    }

    func focusTerminal() {
        shouldAutoFocusOnReady = false
        window?.makeFirstResponder(self)
        evaluateJavaScript("window.termBridge && window.termBridge.focus();")
    }

    func sendInput(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        session?.write(data)
    }

    func suppressAutoFocus() {
        shouldAutoFocusOnReady = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        applyAppearanceTheme()
        flushBufferedOutput()
        fitToLogicalSizeIfNeeded(force: true)
        if shouldAutoFocusOnReady {
            focusTerminal()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any], let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "input":
            guard
                let base64 = payload["data"] as? String,
                let data = Data(base64Encoded: base64)
            else {
                return
            }

            session?.write(data)
            onInput?(data)
        case "resize":
            guard
                let columns = payload["cols"] as? Int,
                let rows = payload["rows"] as? Int,
                columns > 1,
                rows > 1
            else {
                return
            }

            let nextSize = TerminalGridSize(columns: columns, rows: rows)
            guard nextSize != lastGridSize else {
                return
            }

            lastGridSize = nextSize
            session?.resize(nextSize)
        default:
            break
        }
    }

    private func applyAppearanceTheme() {
        switch appearanceTheme {
        case .dark:
            underPageBackgroundColor = .black
        case .light:
            underPageBackgroundColor = NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.935, alpha: 1)
        }

        guard isReady else {
            return
        }

        let themeName = appearanceTheme == .light ? "light" : "dark"
        evaluateJavaScript("window.termBridge && window.termBridge.applyTheme('\(themeName)');")
    }

    private func loadFrontend() {
        guard let url = AppResourceLocator.terminalFrontendURL() else {
            loadHTMLString(
                """
                <html><body style="background:#111;color:#fff;font-family:Menlo,monospace;padding:24px;">Missing terminal frontend resources.</body></html>
                """,
                baseURL: nil
            )
            return
        }

        loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func startSession() {
        do {
            let session = try TerminalSession(initialSize: lastGridSize)
            session.onData = { [weak self] data in
                self?.appendOutput(data)
            }
            session.onExit = { [weak self] in
                self?.evaluateJavaScript("window.termBridge && window.termBridge.markExited();")
            }
            self.session = session
        } catch {
            loadHTMLString(
                """
                <html>
                <body style="margin:0;background:#090b10;color:#ffb4b4;font:13px Menlo, monospace;display:flex;align-items:center;justify-content:center;padding:24px;">
                  <div>Unable to start the shell.<br><br>\(error.localizedDescription)</div>
                </body>
                </html>
                """,
                baseURL: nil
            )
        }
    }

    private func appendOutput(_ data: Data, persist: Bool = true) {
        guard !data.isEmpty else {
            return
        }

        if persist {
            onOutput?(data)
        }

        let chunkSize = 24 * 1024
        var offset = data.startIndex

        while offset < data.endIndex {
            let end = min(offset + chunkSize, data.endIndex)
            let payload = data[offset..<end].base64EncodedString()

            if isReady {
                evaluateJavaScript("window.termBridge && window.termBridge.writeBase64('\(payload)');")
            } else {
                bufferedChunks.append(payload)
            }

            offset = end
        }
    }

    private func flushBufferedOutput() {
        guard isReady, !bufferedChunks.isEmpty else {
            return
        }

        let queued = bufferedChunks
        bufferedChunks.removeAll(keepingCapacity: true)

        for chunk in queued {
            evaluateJavaScript("window.termBridge && window.termBridge.writeBase64('\(chunk)');")
        }
    }

    private func fitToLogicalSizeIfNeeded(force: Bool = false) {
        guard isReady, logicalSize.width > 0, logicalSize.height > 0 else {
            return
        }

        guard force || lastFittedLogicalSize != logicalSize else {
            return
        }

        lastFittedLogicalSize = logicalSize
        evaluateJavaScript("window.termBridge && window.termBridge.fit();")
    }
}

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
