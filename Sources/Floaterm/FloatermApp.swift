import AppKit
import SwiftUI
import Combine

@main
struct FloatermApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var appState = AppState()
    var ptyManager = PTYManager()
    var canvasView: CanvasView!
    var inputController: CanvasInputController!
    var terminalContainer: NSView!
    var terminalBoxViews: [String: TerminalBoxView] = [:]
    private var saveDebounce: AnyCancellable?
    private var saveEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load theme
        appState.theme = ThemeManager.loadTheme()

        // Create window
        let windowRect = NSRect(
            x: 0, y: 0,
            width: Dimensions.defaultWindowWidth,
            height: Dimensions.defaultWindowHeight
        )
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "floaterm"
        window.center()
        window.minSize = NSSize(width: 600, height: 400)
        window.backgroundColor = Colors.bg(for: appState.theme)

        // Build the menu bar
        buildMenuBar()

        // Content view
        let contentView = FlippedView(frame: windowRect)
        window.contentView = contentView

        // Layer 0: Canvas
        canvasView = CanvasView(frame: contentView.bounds)
        canvasView.autoresizingMask = [.width, .height]
        canvasView.theme = appState.theme
        contentView.addSubview(canvasView)

        // Layer 1: Terminal container
        terminalContainer = PassthroughView(frame: contentView.bounds)
        terminalContainer.autoresizingMask = [.width, .height]
        contentView.addSubview(terminalContainer)

        // Layer 2: Individual SwiftUI overlay panels (not one giant hosting view)
        addOverlayPanel(
            rootView: ToolbarView(appState: appState)
                .onTapGesture { [weak self] in
                    if self?.appState.activeTool == .spawn { self?.spawnInCenter() }
                },
            to: contentView,
            alignment: .topCenter
        )

        addOverlayPanel(
            rootView: HStack(spacing: 8) {
                QuickSpawnMenu(appState: appState, onSpawn: { [weak self] label, cmd in
                    self?.spawnWithCommand(label: label, command: cmd)
                })
                TerminalListPopover(
                    appState: appState,
                    onFocus: { [weak self] id in self?.focusTerminal(id: id) },
                    onClose: { [weak self] id in self?.closeTerminal(id: id) },
                    onRename: { [weak self] id, label in self?.renameTerminal(id: id, label: label) }
                )
            },
            to: contentView,
            alignment: .topRight
        )

        addOverlayPanel(
            rootView: ZoomBar(
                appState: appState,
                onReset: { [weak self] in self?.resetZoom() },
                onToggleTheme: { [weak self] in self?.toggleTheme() }
            ),
            to: contentView,
            alignment: .bottomLeft
        )

        // Logo (non-interactive)
        let logoView = NSHostingView(rootView:
            HStack(spacing: 6) {
                Image(systemName: "terminal").font(.system(size: 14))
                Text("floaterm").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .opacity(0.7)
        )
        logoView.frame = NSRect(x: 16, y: 14, width: 120, height: 24)
        logoView.wantsLayer = true
        logoView.layer?.backgroundColor = .clear
        contentView.addSubview(logoView)

        // Input controller
        inputController = CanvasInputController()
        inputController.canvasView = canvasView
        inputController.appState = appState
        inputController.onBoxCreated = { [weak self] box in
            self?.createTerminalView(for: box)
        }
        inputController.onBoxChanged = { [weak self] in
            self?.updateAllTerminalPositions()
            self?.scheduleSave()
        }

        // Wire canvas events
        let eventView = canvasView!
        eventView.onMouseDown = { [weak self] event in self?.inputController.mouseDown(with: event, in: eventView) }
        eventView.onMouseDragged = { [weak self] event in self?.inputController.mouseDragged(with: event, in: eventView) }
        eventView.onMouseUp = { [weak self] event in self?.inputController.mouseUp(with: event, in: eventView) }
        eventView.onScrollWheel = { [weak self] event in self?.inputController.scrollWheel(with: event, in: eventView) }
        eventView.onKeyDown = { [weak self] event in self?.inputController.keyDown(with: event) }

        // Restore state
        restoreState()

        // Debounced save
        saveDebounce = appState.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveState()
            }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Enable saves after restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.saveEnabled = true
        }

        // DEBUG: Self-test after 3 seconds (no spawn, just check hitTest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.runSelfTest()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveState()
        ptyManager.cleanup()
    }

    // MARK: - Terminal lifecycle

    private func createTerminalView(for box: TerminalBox) {
        let boxView = TerminalBoxView(box: box)
        boxView.frame = frameForBox(box)
        boxView.layer?.anchorPoint = CGPoint(x: 0, y: 0)
        boxView.layer?.transform = CATransform3DMakeScale(appState.transform.scale, appState.transform.scale, 1)

        boxView.onDragStart = { [weak self] id, point in
            self?.inputController.startDragBox(id: id, windowPoint: point)
        }
        boxView.onDragMoved = { [weak self] event in
            self?.inputController.dragBoxMoved(with: event)
        }
        boxView.onDragEnded = { [weak self] event in
            self?.inputController.dragBoxEnded(with: event)
        }
        boxView.onResizeStart = { [weak self] id, handle, event in
            self?.inputController.startResizeBox(id: id, handle: handle, event: event)
        }
        boxView.onResizeMoved = { [weak self] event in
            self?.inputController.resizeBoxMoved(with: event)
        }
        boxView.onResizeEnded = { [weak self] event in
            self?.inputController.resizeBoxEnded(with: event)
        }
        boxView.onFocus = { [weak self] id in self?.focusTerminal(id: id) }
        boxView.onClose = { [weak self] id in self?.closeTerminal(id: id) }
        boxView.onLabelChanged = { [weak self] id, label in self?.renameTerminal(id: id, label: label) }

        terminalContainer.addSubview(boxView)
        terminalBoxViews[box.id] = boxView

        // Spawn PTY
        let dims = boxView.updateCols()
        let cmd: String? = nil // default shell
        let session = ptyManager.getOrCreate(id: box.id, cols: dims.cols, rows: dims.rows, command: cmd)
        boxView.connectPTY(session)
        boxView.setFocused(box.focused)
    }

    private func updateAllTerminalPositions() {
        for box in appState.boxes {
            guard let view = terminalBoxViews[box.id] else { continue }
            view.frame = frameForBox(box)
            view.layer?.transform = CATransform3DMakeScale(appState.transform.scale, appState.transform.scale, 1)
        }
        canvasView.transform = appState.transform
        canvasView.shapes = appState.shapes
    }

    private func frameForBox(_ box: TerminalBox) -> NSRect {
        let screen = appState.transform.worldToScreen(wx: box.x, wy: box.y)
        return NSRect(x: screen.x, y: screen.y, width: box.w, height: box.h)
    }

    // MARK: - Actions

    private func spawnInCenter() {
        let box = appState.spawnInCenter(windowSize: window.contentView!.bounds.size)
        appState.addBox(box)
        createTerminalView(for: box)
        scheduleSave()
    }

    private func spawnWithCommand(label: String, command: String) {
        let box = appState.spawnWithCommand(label: label, windowSize: window.contentView!.bounds.size)
        appState.addBox(box)

        let boxView = TerminalBoxView(box: box)
        boxView.frame = frameForBox(box)
        boxView.layer?.anchorPoint = CGPoint(x: 0, y: 0)
        boxView.layer?.transform = CATransform3DMakeScale(appState.transform.scale, appState.transform.scale, 1)

        boxView.onDragStart = { [weak self] id, point in self?.inputController.startDragBox(id: id, windowPoint: point) }
        boxView.onDragMoved = { [weak self] event in self?.inputController.dragBoxMoved(with: event) }
        boxView.onDragEnded = { [weak self] event in self?.inputController.dragBoxEnded(with: event) }
        boxView.onResizeStart = { [weak self] id, handle, event in self?.inputController.startResizeBox(id: id, handle: handle, event: event) }
        boxView.onResizeMoved = { [weak self] event in self?.inputController.resizeBoxMoved(with: event) }
        boxView.onResizeEnded = { [weak self] event in self?.inputController.resizeBoxEnded(with: event) }
        boxView.onFocus = { [weak self] id in self?.focusTerminal(id: id) }
        boxView.onClose = { [weak self] id in self?.closeTerminal(id: id) }
        boxView.onLabelChanged = { [weak self] id, label in self?.renameTerminal(id: id, label: label) }

        terminalContainer.addSubview(boxView)
        terminalBoxViews[box.id] = boxView

        let dims = boxView.updateCols()
        let session = ptyManager.getOrCreate(id: box.id, cols: dims.cols, rows: dims.rows, command: command)
        boxView.connectPTY(session)
        boxView.setFocused(true)
        scheduleSave()
    }

    private func focusTerminal(id: String) {
        appState.focusBox(id: id)
        for (boxId, view) in terminalBoxViews {
            view.setFocused(boxId == id)
            if boxId == id {
                view.removeFromSuperview()
                terminalContainer.addSubview(view) // bring to front
            }
        }
    }

    private func closeTerminal(id: String) {
        ptyManager.destroy(id: id)
        terminalBoxViews[id]?.removeFromSuperview()
        terminalBoxViews.removeValue(forKey: id)
        appState.removeBox(id: id)
        scheduleSave()
    }

    private func renameTerminal(id: String, label: String) {
        guard let idx = appState.boxIndex(id: id) else { return }
        appState.boxes[idx].label = label
        terminalBoxViews[id]?.updateLabel(label)
        scheduleSave()
    }

    private func resetZoom() {
        appState.transform.reset()
        updateAllTerminalPositions()
        scheduleSave()
    }

    private func toggleTheme() {
        appState.theme = appState.theme == .dark ? .light : .dark
        canvasView.theme = appState.theme
        window.backgroundColor = Colors.bg(for: appState.theme)
        ThemeManager.saveTheme(appState.theme)
    }

    // MARK: - Persistence

    private func scheduleSave() {
        guard saveEnabled else { return }
        // Debouncing handled by Combine subscription
        appState.objectWillChange.send()
    }

    private func saveState() {
        guard saveEnabled else { return }
        let state = PersistedState(
            canvas: appState.transform,
            boxes: appState.boxes,
            shapes: appState.shapes
        )
        StatePersistence.save(state)
    }

    private func restoreState() {
        guard let state = StatePersistence.load() else { return }
        appState.transform = state.canvas
        appState.shapes = state.shapes
        canvasView.transform = appState.transform
        canvasView.shapes = appState.shapes

        for box in state.boxes {
            appState.addBox(box)
            createTerminalView(for: box)
        }
    }

    // MARK: - Overlay panels

    enum OverlayAlignment { case topCenter, topRight, bottomLeft }

    private func addOverlayPanel<V: View>(rootView: V, to parent: NSView, alignment: OverlayAlignment) {
        let hosting = ClickableHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        // Size to fit content
        let fittingSize = hosting.fittingSize
        let parentBounds = parent.bounds

        var origin: NSPoint
        switch alignment {
        case .topCenter:
            origin = NSPoint(x: (parentBounds.width - fittingSize.width) / 2, y: 12)
        case .topRight:
            origin = NSPoint(x: parentBounds.width - fittingSize.width - 16, y: 12)
        case .bottomLeft:
            origin = NSPoint(x: 16, y: parentBounds.height - fittingSize.height - 12)
        }

        hosting.frame = NSRect(origin: origin, size: fittingSize)

        // Auto-resize with superview
        switch alignment {
        case .topCenter:
            hosting.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        case .topRight:
            hosting.autoresizingMask = [.minXMargin, .maxYMargin]
        case .bottomLeft:
            hosting.autoresizingMask = [.maxXMargin, .minYMargin]
        }

        parent.addSubview(hosting)
    }

    // MARK: - Self test

    private func runSelfTest() {
        NSLog("=== SELF TEST START ===")
        let cv = canvasView!
        let bounds = cv.bounds
        NSLog("[TEST] Canvas bounds: \(bounds)")
        NSLog("[TEST] Canvas isFlipped: \(cv.isFlipped)")
        NSLog("[TEST] Canvas acceptsFirstResponder: \(cv.acceptsFirstResponder)")
        NSLog("[TEST] Canvas onMouseDown set: \(cv.onMouseDown != nil)")
        NSLog("[TEST] Canvas onScrollWheel set: \(cv.onScrollWheel != nil)")
        NSLog("[TEST] Active tool: \(appState.activeTool)")
        NSLog("[TEST] Transform: offset=(\(appState.transform.offsetX), \(appState.transform.offsetY)) scale=\(appState.transform.scale)")

        // Test hitTest at various points
        let testPoints: [(String, NSPoint)] = [
            ("center", NSPoint(x: 600, y: 400)),
            ("top-left canvas", NSPoint(x: 100, y: 100)),
            ("toolbar area", NSPoint(x: 600, y: 20)),
            ("zoom bar area", NSPoint(x: 50, y: 780)),
            ("quick spawn area", NSPoint(x: 1100, y: 20)),
        ]
        for (label, pt) in testPoints {
            let hit = window.contentView?.hitTest(pt)
            let desc = hit.map { String(describing: type(of: $0)) } ?? "nil"
            NSLog("[TEST] hitTest '\(label)' at \(pt) -> \(desc)")
        }

        // Test spawn
        NSLog("[TEST] Boxes from restore: \(appState.boxes.count)")
        NSLog("[TEST] Shapes from restore: \(appState.shapes.count)")

        // Log all subviews of contentView with frames
        let cv2 = window.contentView!
        for (i, sub) in cv2.subviews.enumerated() {
            NSLog("[TEST] contentView.subview[\(i)] = \(type(of: sub)) frame=\(sub.frame) hidden=\(sub.isHidden)")
        }

        // Direct hitTest on toolbar's hosting view
        let toolbarHosting = cv2.subviews[2] // toolbar
        let toolbarCenter = NSPoint(x: toolbarHosting.frame.midX, y: toolbarHosting.frame.midY)
        let toolbarHit = cv2.hitTest(toolbarCenter)
        NSLog("[TEST] toolbar direct hitTest at \(toolbarCenter) -> \(toolbarHit.map { String(describing: type(of: $0)) } ?? "nil")")

        // Also test if the toolbar hosting view itself gets the hit
        let localPoint = toolbarHosting.convert(toolbarCenter, from: cv2)
        let directHit = toolbarHosting.hitTest(localPoint)
        NSLog("[TEST] toolbar LOCAL hitTest at local=\(localPoint) -> \(directHit.map { String(describing: type(of: $0)) } ?? "nil")")

        NSLog("=== SELF TEST DONE ===")
    }

    // MARK: - Menu bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About floaterm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide floaterm", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit floaterm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}

// (OverlayView removed — using individual overlay panels instead)

// MARK: - Helper views

/// A flipped NSView (origin at top-left, like HTML)
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// NSHostingView that always accepts clicks within its bounds.
/// SwiftUI's internal hitTest often returns nil when embedded in AppKit,
/// so we force it to accept events, letting SwiftUI handle routing internally.
private class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // hitTest point is in UNFLIPPED superview coords (origin bottom-left)
        // But our frame is in FLIPPED coords (origin top-left) because superview.isFlipped = true
        // Need to flip the point's Y to match our frame's coordinate space
        guard let sv = superview else { return nil }
        let flippedY = sv.bounds.height - point.y
        let flippedPoint = NSPoint(x: point.x, y: flippedY)
        if frame.contains(flippedPoint) {
            return self
        }
        return nil
    }
}

/// An NSView that passes through mouse events when no child is hit
private class PassthroughView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

/// NSHostingView that lets mouse events pass through empty areas to views below.
/// Only intercepts clicks that actually land on a SwiftUI control.
private class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Our parent is flipped (origin top-left) but NSHostingView is NOT flipped
        // (origin bottom-left). We need to flip the Y coordinate for super.hitTest.
        let flippedPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        let result = super.hitTest(flippedPoint)
        // Pass through if nothing was hit, or only the hosting view background
        if result == nil || result === self {
            return nil
        }
        return result
    }
}
