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
        case creating(startScreen: CGPoint, currentScreen: CGPoint)
    }

    private weak var store: CanvasStore?
    private var nodeViews: [UUID: TerminalNodeView] = [:]
    private var interaction: Interaction?
    private var previewWorldRect: CGRect?
    private var hasBootstrappedCamera = false
    private var spacebarIsDown = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
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

        syncNodeViews()
        needsDisplay = true
    }

    func apply(store: CanvasStore) {
        self.store = store
        store.updateViewportSize(bounds.size)

        if !hasBootstrappedCamera, !bounds.size.equalTo(.zero) {
            store.bootstrapCameraIfNeeded(center: CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.5))
            hasBootstrappedCamera = true
        }

        syncNodeViews()
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
            let previewRect = CanvasGeometry.worldToScreen(previewWorldRect, camera: store.camera)
            let previewPath = NSBezierPath(roundedRect: previewRect, xRadius: 18, yRadius: 18)
            NSColor.systemMint.withAlphaComponent(0.14).setFill()
            previewPath.fill()

            previewPath.lineWidth = 2
            previewPath.setLineDash([10, 7], count: 2, phase: 0)
            NSColor.systemMint.withAlphaComponent(0.9).setStroke()
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
            store.selectNode(nil)
        case .terminal:
            interaction = .creating(startScreen: location, currentScreen: location)
            previewWorldRect = CanvasGeometry.normalizedWorldRect(from: location, to: location, camera: store.camera)
            needsDisplay = true
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
        case let .creating(startScreen, _):
            self.interaction = .creating(startScreen: startScreen, currentScreen: location)
            previewWorldRect = CanvasGeometry.normalizedWorldRect(from: startScreen, to: location, camera: store.camera)
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let store else {
            interaction = nil
            previewWorldRect = nil
            needsDisplay = true
            return
        }

        defer {
            interaction = nil
            previewWorldRect = nil
            needsDisplay = true
        }

        guard let interaction else {
            return
        }

        switch interaction {
        case .panning:
            return
        case let .creating(startScreen, currentScreen):
            var frame = CanvasGeometry.normalizedWorldRect(from: startScreen, to: currentScreen, camera: store.camera)

            if frame.width < 24 || frame.height < 24 {
                let worldPoint = CanvasGeometry.screenToWorld(currentScreen, camera: store.camera)
                frame = CGRect(
                    x: worldPoint.x - CanvasGeometry.defaultNodeSize.width * 0.5,
                    y: worldPoint.y - CanvasGeometry.defaultNodeSize.height * 0.5,
                    width: CanvasGeometry.defaultNodeSize.width,
                    height: CanvasGeometry.defaultNodeSize.height
                )
            }

            _ = store.createTerminal(frame: frame)
            store.tool = .select
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
    }

    override func magnify(with event: NSEvent) {
        guard let store else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        store.zoom(by: 1 + event.magnification, around: location)
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
            store.removeSelectedNode()
            return
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "t":
            store.tool = .terminal
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
                    self?.store?.moveNode(id: node.id, byScreenDelta: delta)
                }
                created.onResize = { [weak self] handle, delta in
                    self?.store?.resizeNode(id: node.id, handle: handle, byScreenDelta: delta)
                }
                created.onClose = { [weak self] in
                    self?.store?.removeNode(id: node.id)
                }
                created.onChromeActivation = { [weak self] in
                    self?.store?.selectNode(node.id)
                    self?.window?.makeFirstResponder(self)
                }
                created.onTerminalActivation = { [weak self, weak created] in
                    self?.store?.selectNode(node.id)
                    created?.focusTerminal()
                }
                addSubview(created)
                nodeViews[node.id] = created
                view = created
            }

            view.title = node.title
            view.isSelected = store.selectedNodeID == node.id
            view.layer?.zPosition = CGFloat(index) + (view.isSelected ? 1_000 : 0)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.frame = CanvasGeometry.worldToScreen(node.frame, camera: store.camera)
            CATransaction.commit()
        }
    }

    private func drawGrid(camera: CanvasCamera, in dirtyRect: NSRect) {
        let step = CanvasGeometry.adaptiveGridStep(for: camera)
        let majorStep = step * 4
        let visibleMinWorld = CanvasGeometry.screenToWorld(CGPoint(x: dirtyRect.minX, y: dirtyRect.minY), camera: camera)
        let visibleMaxWorld = CanvasGeometry.screenToWorld(CGPoint(x: dirtyRect.maxX, y: dirtyRect.maxY), camera: camera)

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
}

final class TerminalNodeView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onResize: ((ResizeHandle, CGPoint) -> Void)?
    var onClose: (() -> Void)?
    var onChromeActivation: (() -> Void)?
    var onTerminalActivation: (() -> Void)?

    var title: String {
        get { titleField.stringValue }
        set { titleField.stringValue = newValue }
    }

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    private let headerHeight: CGFloat = 36
    private let contentInset: CGFloat = 10
    private let edgeHandleThickness: CGFloat = 10
    private let cornerHandleSize: CGFloat = 18

    private let headerView = DragHeaderView()
    private let titleField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let terminalView = TerminalWebView()
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

        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -10)
        layer?.shadowRadius = 18
        layer?.shadowOpacity = 0.22
        layer?.masksToBounds = false

        titleField.stringValue = title
        titleField.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail

        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close terminal")
        closeButton.contentTintColor = .systemRed
        closeButton.bezelStyle = .regularSquare
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.toolTip = "Close terminal"

        headerView.onActivate = { [weak self] in
            self?.onChromeActivation?()
        }
        headerView.onDrag = { [weak self] delta in
            self?.onMove?(delta)
        }

        terminalView.onActivate = { [weak self] in
            self?.onTerminalActivation?()
        }

        addSubview(terminalView)
        addSubview(headerView)
        headerView.addSubview(titleField)
        headerView.addSubview(closeButton)

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

        let headerRect = CGRect(
            x: contentInset,
            y: bounds.height - headerHeight - contentInset,
            width: bounds.width - (contentInset * 2),
            height: headerHeight
        )
        headerView.frame = headerRect

        closeButton.frame = CGRect(x: 10, y: 8, width: 20, height: 20)
        titleField.frame = CGRect(
            x: closeButton.frame.maxX + 8,
            y: 7,
            width: headerRect.width - closeButton.frame.maxX - 18,
            height: 22
        )

        terminalView.frame = CGRect(
            x: contentInset,
            y: contentInset,
            width: bounds.width - (contentInset * 2),
            height: bounds.height - headerHeight - (contentInset * 2) - 4
        )

        layoutResizeHandles()
    }

    @objc
    private func handleClose() {
        onClose?()
    }

    func focusTerminal() {
        terminalView.focusTerminal()
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 0.96).cgColor
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = (isSelected ? NSColor.systemMint : NSColor.white.withAlphaComponent(0.12)).cgColor
        layer?.shadowOpacity = isSelected ? 0.28 : 0.18
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

final class DragHeaderView: NSView {
    var onDrag: ((CGPoint) -> Void)?
    var onActivate: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.20, alpha: 0.96).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
    }
}

final class ResizeHandleView: NSView {
    let handle: ResizeHandle
    var onDrag: ((ResizeHandle, CGPoint) -> Void)?
    var onActivate: (() -> Void)?

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
        default:
            cursor = .crosshair
        }

        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(handle, CanvasInputMapping.mouseDragDelta(deltaX: event.deltaX, deltaY: event.deltaY))
    }
}

final class TerminalWebView: WKWebView, WKNavigationDelegate, WKScriptMessageHandler {
    var onActivate: (() -> Void)?

    private var session: TerminalSession?
    private var isReady = false
    private var bufferedChunks: [String] = []
    private var lastGridSize = TerminalGridSize(columns: 100, rows: 30)

    init() {
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()

        super.init(frame: .zero, configuration: configuration)

        controller.add(WeakScriptMessageHandler(delegate: self), name: "terminal")
        navigationDelegate = self
        setValue(false, forKey: "drawsBackground")
        underPageBackgroundColor = .clear
        layer?.cornerRadius = 14
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
        focusTerminal()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any], let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            isReady = true
            flushBufferedOutput()
            session?.resize(lastGridSize)
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
