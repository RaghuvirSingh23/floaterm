import AppKit
import SwiftUI
import WebKit

struct CanvasViewRepresentable: NSViewRepresentable {
    @ObservedObject var store: CanvasStore

    func makeNSView(context: Context) -> CanvasViewportView {
        let view = CanvasViewportView()
        view.apply(store: store)
        return view
    }

    func updateNSView(_ nsView: CanvasViewportView, context: Context) {
        nsView.apply(store: store)
    }
}

final class CanvasViewportView: NSView {
    private enum Interaction {
        case panning(anchor: CGPoint, initialPan: CGPoint)
        case creatingTerminal(startScreen: CGPoint, currentScreen: CGPoint)
        case marqueeSelecting(startScreen: CGPoint, currentScreen: CGPoint, appendToSelection: Bool)
    }

    private enum PreviewStyle {
        case terminalCreation
        case selection

        var fillColor: NSColor {
            switch self {
            case .terminalCreation:
                return NSColor.systemMint.withAlphaComponent(0.14)
            case .selection:
                return NSColor.systemBlue.withAlphaComponent(0.12)
            }
        }

        var strokeColor: NSColor {
            switch self {
            case .terminalCreation:
                return NSColor.systemMint.withAlphaComponent(0.9)
            case .selection:
                return NSColor.systemBlue.withAlphaComponent(0.96)
            }
        }

        var dashPattern: [CGFloat] {
            switch self {
            case .terminalCreation:
                return [10, 7]
            case .selection:
                return [8, 5]
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .terminalCreation:
                return 18
            case .selection:
                return 10
            }
        }
    }

    private weak var store: CanvasStore?
    private let worldView = NSView()
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
        needsDisplay = true
    }

    func apply(store: CanvasStore) {
        self.store = store
        store.updateViewportSize(bounds.size)

        if !hasBootstrappedCamera, !bounds.size.equalTo(.zero) {
            store.bootstrapCameraIfNeeded(center: CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.5))
            hasBootstrappedCamera = true
        }

        updateWorldViewTransform()
        syncElementViews()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let store else {
            return
        }

        let background = NSRect(origin: .zero, size: bounds.size)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.11, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.06, alpha: 1),
        ])
        gradient?.draw(in: background, angle: 90)

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
        case .text:
            _ = store.createText(at: worldPoint(fromScreenPoint: location))
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

        if event.keyCode == 49 {
            spacebarIsDown = true
            return
        }

        switch event.keyCode {
        case 51, 117:
            store.deleteSelection()
            return
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "t":
            store.tool = .terminal
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
        syncNodeViews()
        syncTextViews()
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
                let created = TerminalNodeView(title: node.title)
                created.onMove = { [weak self] delta in
                    self?.store?.moveSelection(anchorID: node.id, byScreenDelta: delta)
                }
                created.onResize = { [weak self] handle, delta in
                    self?.store?.resizeNode(id: node.id, handle: handle, byScreenDelta: delta)
                }
                created.onClose = { [weak self] in
                    self?.store?.removeNode(id: node.id)
                }
                created.onChromeActivation = { [weak self] in
                    self?.store?.activateElement(node.id)
                    self?.window?.makeFirstResponder(self)
                }
                created.onTerminalActivation = { [weak self, weak created] in
                    self?.store?.activateElement(node.id)
                    created?.focusTerminal()
                }
                created.onTitleCommit = { [weak self] title in
                    self?.store?.renameNode(id: node.id, title: title)
                }
                worldView.addSubview(created)
                nodeViews[node.id] = created
                view = created
            }

            view.title = node.title
            view.isSelected = store.selectedElementIDs.contains(node.id)
            view.layer?.zPosition = CGFloat(index) + (view.isSelected ? 1_000 : 0)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = node.frame
            CATransaction.commit()
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
                created.onActivate = { [weak self] in
                    self?.store?.activateElement(item.id)
                    self?.window?.makeFirstResponder(self)
                }
                created.onMove = { [weak self] delta in
                    self?.store?.moveSelection(anchorID: item.id, byScreenDelta: delta)
                }
                created.onResize = { [weak self] handle, delta in
                    self?.store?.resizeTextItem(id: item.id, handle: handle, byScreenDelta: delta)
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
            view.isSelected = store.selectedElementIDs.contains(item.id)
            view.layer?.zPosition = 10_000 + CGFloat(index) + (view.isSelected ? 1_000 : 0)

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
            color: NSColor.white.withAlphaComponent(0.05),
            camera: camera
        )
        drawGridLines(
            from: visibleMinWorld,
            to: visibleMaxWorld,
            step: majorStep,
            lineWidth: 1.2,
            color: NSColor.systemMint.withAlphaComponent(0.08),
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
}

final class TerminalNodeView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onResize: ((ResizeHandle, CGPoint) -> Void)?
    var onClose: (() -> Void)?
    var onChromeActivation: (() -> Void)?
    var onTerminalActivation: (() -> Void)?
    var onTitleCommit: ((String) -> Void)?

    var title = "" {
        didSet {
            titleField.stringValue = title
        }
    }

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    private let shellInset: CGFloat = 4
    private let shellCornerRadius: CGFloat = 10
    private let titlebarInset: CGFloat = 1
    private let titlebarHeight: CGFloat = 24
    private let titleHorizontalInset: CGFloat = 84
    private let contentHorizontalInset: CGFloat = 1
    private let contentBottomInset: CGFloat = 1
    private let contentTopGap: CGFloat = 1
    private let closeButtonLeadingInset: CGFloat = 12
    private let closeButtonSize: CGFloat = 10
    private let chromeLineWidth: CGFloat = 1
    private let separatorHeight: CGFloat = 1
    private let edgeHandleThickness: CGFloat = 10
    private let cornerHandleSize: CGFloat = 18

    private let shellView = TerminalOutlineView()
    private let titlebarView = TerminalOutlineView()
    private let titlebarSeparatorView = TerminalOutlineView()
    private let terminalFrameView = TerminalOutlineView()
    private let dragStripView = DragHeaderView()
    private let titleField = EditableCanvasTextField()
    private let closeButton = CursorButton()
    private let terminalView = TerminalWebView()
    private var contentBottomCornerRadius: CGFloat {
        max(shellCornerRadius - shellInset, 0)
    }
    private lazy var handles: [ResizeHandle: ResizeHandleView] = ResizeHandle.allCases.reduce(into: [:]) { result, handle in
        let view = ResizeHandleView(handle: handle)
        view.onActivate = { [weak self] in
            self?.onChromeActivation?()
        }
        view.onDrag = { [weak self] dragHandle, delta in
            self?.onResize?(dragHandle, delta)
        }
        result[handle] = view
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title

        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = false
        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleField.alignment = .center
        titleField.textColor = NSColor(calibratedWhite: 0.74, alpha: 1)
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.cell?.usesSingleLineMode = true
        titleField.isEditable = true
        titleField.drawsBackground = false
        titleField.isBordered = false
        titleField.focusRingType = .none
        titleField.beginsEditingOnSingleClick = false
        titleField.onActivate = { [weak self] in
            self?.onChromeActivation?()
        }
        titleField.onCommit = { [weak self] title in
            self?.onTitleCommit?(title)
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

        dragStripView.onActivate = { [weak self] in
            self?.onChromeActivation?()
        }
        dragStripView.onDrag = { [weak self] delta in
            self?.onMove?(delta)
        }

        terminalView.onActivate = { [weak self] in
            self?.onTerminalActivation?()
        }

        dragStripView.addSubview(titleField)
        addSubview(shellView)
        addSubview(titlebarView)
        addSubview(titlebarSeparatorView)
        addSubview(terminalFrameView)
        addSubview(terminalView)
        addSubview(dragStripView)

        for handleView in handles.values {
            addSubview(handleView)
        }

        addSubview(closeButton)

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let shellFrame = bounds.insetBy(dx: shellInset, dy: shellInset)
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
        titlebarView.frame = titlebarFrame
        titlebarSeparatorView.frame = separatorFrame
        dragStripView.frame = titlebarFrame
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = CGRect(
            x: titleHorizontalInset,
            y: floor((titlebarFrame.height - titleHeight) * 0.5),
            width: max(titlebarFrame.width - (titleHorizontalInset * 2), 40),
            height: titleHeight
        )
        terminalView.frame = contentFrame
        terminalView.logicalSize = contentFrame.size
        terminalView.layer?.cornerRadius = contentBottomCornerRadius
        terminalView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        terminalFrameView.frame = contentFrame.insetBy(dx: -1, dy: -1)
        closeButton.frame = CGRect(
            x: titlebarFrame.minX + closeButtonLeadingInset,
            y: titlebarFrame.midY - (closeButtonSize * 0.5),
            width: closeButtonSize,
            height: closeButtonSize
        )
        closeButton.layer?.cornerRadius = closeButtonSize * 0.5
        dragStripView.cursorExclusionRect = CGRect(
            x: closeButton.frame.minX - titlebarFrame.minX - 6,
            y: 0,
            width: closeButton.frame.width + 12,
            height: titlebarFrame.height
        )

        layoutResizeHandles()
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !closeButton.isHidden, closeButton.frame.contains(point) {
            let buttonPoint = convert(point, to: closeButton)
            return closeButton.hitTest(buttonPoint) ?? closeButton
        }

        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        if !closeButton.isHidden {
            addCursorRect(closeButton.frame, cursor: .pointingHand)
        }
    }

    @objc
    private func handleClose() {
        onClose?()
    }

    func focusTerminal() {
        terminalView.focusTerminal()
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.shadowOpacity = 0
        let shellBorderColor = NSColor(calibratedWhite: isSelected ? 0.34 : 0.26, alpha: 1)
        let shellFillColor = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.14, alpha: 0.98)
        let titlebarFillColor = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 0.98)
        let separatorColor = NSColor(calibratedWhite: 0.30, alpha: 1)
        let contentBorderColor = NSColor(calibratedWhite: isSelected ? 0.25 : 0.20, alpha: 1)
        let titleColor = NSColor(calibratedWhite: isSelected ? 0.84 : 0.70, alpha: 1)
        let closeButtonFillColor = NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.33, alpha: isSelected ? 1 : 0.92)
        let closeButtonGlyphColor = NSColor(calibratedRed: 0.34, green: 0.12, blue: 0.11, alpha: 0.96)

        closeButton.isHidden = false
        closeButton.contentTintColor = closeButtonGlyphColor
        closeButton.layer?.backgroundColor = closeButtonFillColor.cgColor
        titleField.textColor = titleColor

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
    var onActivate: (() -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onResize: ((ResizeHandle, CGPoint) -> Void)?
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

    private let textView = EditableCanvasTextView()
    private let horizontalPadding = CanvasGeometry.textPadding.width * 0.5
    private let verticalPadding = CanvasGeometry.textPadding.height * 0.5
    private let edgeHandleThickness: CGFloat = 10
    private let cornerHandleSize: CGFloat = 18
    private lazy var handles: [ResizeHandle: ResizeHandleView] = [ResizeHandle.left, .right].reduce(into: [ResizeHandle: ResizeHandleView]()) { result, handle in
        let view = ResizeHandleView(handle: handle)
        view.onActivate = { [weak self] in
            self?.onActivate?()
        }
        view.onDrag = { [weak self] handle, delta in
            self?.onResize?(handle, delta)
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
        textView.onActivate = { [weak self] in
            self?.onActivate?()
        }
        textView.onDrag = { [weak self] delta in
            self?.onMove?(delta)
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
        onActivate?()
        textView.beginEditing()
    }

    private func updateAppearance() {
        let showSelection = isSelected && !textView.isEditing
        layer?.backgroundColor = showSelection ? NSColor.systemBlue.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
        layer?.borderColor = showSelection ? NSColor.systemBlue.withAlphaComponent(0.85).cgColor : NSColor.clear.cgColor
        layer?.borderWidth = showSelection ? 1.25 : 0
        layer?.cornerRadius = 9
        for handleView in handles.values {
            handleView.isHidden = !showSelection
        }
    }
}

final class EditableCanvasTextField: NSTextField, NSTextFieldDelegate {
    var onActivate: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onCommit: ((String) -> Void)?
    var beginsEditingOnSingleClick = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if currentEditor() != nil {
            super.mouseDown(with: event)
            return
        }

        onActivate?()

        guard beginsEditingOnSingleClick || event.clickCount >= 2 else {
            return
        }

        beginEditing()
    }

    override func mouseDragged(with event: NSEvent) {
        guard currentEditor() == nil else {
            return
        }

        onDrag?(CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
    }

    func beginEditing() {
        window?.makeFirstResponder(self)
        selectText(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onCommit?(stringValue)
    }
}

final class EditableCanvasTextView: NSView, NSTextViewDelegate {
    var onActivate: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
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
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.allowsUndo = true
        textView.isEditable = false
        textView.isSelectable = false
        textView.onActivate = { [weak self] in
            self?.onActivate?()
        }
        textView.onDrag = { [weak self] delta in
            self?.onDrag?(delta)
        }
        textView.onCommit = { [weak self] in
            self?.endEditing()
        }

        addSubview(scrollView)
        configureTextContainer()
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
}

final class CanvasIntrinsicTextView: NSTextView {
    var onActivate: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onCommit: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder === self {
            super.mouseDown(with: event)
            return
        }

        onActivate?()

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

        onDrag?(CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
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
        if didResign, isEditable || isSelectable {
            onCommit?()
        }
        return didResign
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

final class DragHeaderView: NSView {
    var onDrag: ((CGPoint) -> Void)?
    var onActivate: (() -> Void)?
    var cursorExclusionRect: CGRect?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        guard let exclusion = cursorExclusionRect?.intersection(bounds), !exclusion.isEmpty else {
            addCursorRect(bounds, cursor: .openHand)
            return
        }

        let leftWidth = max(exclusion.minX, 0)
        if leftWidth > 0 {
            addCursorRect(
                CGRect(x: 0, y: 0, width: leftWidth, height: bounds.height),
                cursor: .openHand
            )
        }

        let rightX = min(max(exclusion.maxX, 0), bounds.width)
        if rightX < bounds.width {
            addCursorRect(
                CGRect(x: rightX, y: 0, width: bounds.width - rightX, height: bounds.height),
                cursor: .openHand
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
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
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class ResizeHandleView: NSView {
    let handle: ResizeHandle
    var onDrag: ((ResizeHandle, CGPoint) -> Void)?
    var onActivate: (() -> Void)?

    private static let diagonalDescendingCursor = privateResizeCursor(named: "_windowResizeNorthWestSouthEastCursor")
    private static let diagonalAscendingCursor = privateResizeCursor(named: "_windowResizeNorthEastSouthWestCursor")

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
        onActivate?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(handle, CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
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
    var onActivate: (() -> Void)?

    var logicalSize: CGSize = .zero {
        didSet {
            guard oldValue != logicalSize else {
                return
            }

            fitToLogicalSizeIfNeeded()
        }
    }

    private var session: TerminalSession?
    private var isReady = false
    private var bufferedChunks: [String] = []
    private var lastGridSize = TerminalGridSize(columns: 100, rows: 30)
    private var lastFittedLogicalSize: CGSize = .zero

    init() {
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
        startSession()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        session?.close()
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }

    func focusTerminal() {
        window?.makeFirstResponder(self)
        evaluateJavaScript("window.termBridge && window.termBridge.focus();")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        flushBufferedOutput()
        fitToLogicalSizeIfNeeded(force: true)
        focusTerminal()
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

    private func loadFrontend() {
        guard let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Terminal") else {
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

    private func appendOutput(_ data: Data) {
        let payload = data.base64EncodedString()

        if isReady {
            evaluateJavaScript("window.termBridge && window.termBridge.writeBase64('\(payload)');")
        } else {
            bufferedChunks.append(payload)
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
