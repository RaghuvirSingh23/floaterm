import AppKit
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
    var nativeToolbar: NativeToolbarView!
    var nativeZoomBar: NativeZoomBar!
    var nativeSpawnBtn: NativeQuickSpawnButton!
    var nativeTermListBtn: NativeTerminalListButton!
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

        // Content view (standard NSView, NOT flipped — avoids hitTest coordinate hell)
        let contentView = NSView(frame: windowRect)
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

        // Layer 2: Native AppKit UI controls (no SwiftUI — it can't do hitTest)
        let wH = windowRect.height

        // Toolbar (top center)
        nativeToolbar = NativeToolbarView(frame: .zero)
        nativeToolbar.setup(appState: appState, onSpawnCenter: { [weak self] in self?.spawnInCenter() })
        nativeToolbar.frame.origin = NSPoint(x: (windowRect.width - nativeToolbar.frame.width) / 2, y: wH - nativeToolbar.frame.height - 12)
        nativeToolbar.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        contentView.addSubview(nativeToolbar)

        // Quick spawn button (top right, left of terminal list)
        nativeSpawnBtn = NativeQuickSpawnButton()
        nativeSpawnBtn.onSpawnCommand = { [weak self] label, cmd in self?.spawnWithCommand(label: label, command: cmd) }
        nativeSpawnBtn.frame.origin = NSPoint(x: windowRect.width - 160, y: wH - 36)
        nativeSpawnBtn.autoresizingMask = [.minXMargin, .minYMargin]
        contentView.addSubview(nativeSpawnBtn)

        // Terminal list button (top right)
        nativeTermListBtn = NativeTerminalListButton()
        nativeTermListBtn.appState = appState
        nativeTermListBtn.onFocus = { [weak self] id in self?.focusTerminal(id: id) }
        nativeTermListBtn.onClose = { [weak self] id in self?.closeTerminal(id: id) }
        nativeTermListBtn.frame.origin = NSPoint(x: windowRect.width - 76, y: wH - 36)
        nativeTermListBtn.autoresizingMask = [.minXMargin, .minYMargin]
        contentView.addSubview(nativeTermListBtn)

        // Zoom bar (bottom left)
        nativeZoomBar = NativeZoomBar(frame: .zero)
        nativeZoomBar.appState = appState
        nativeZoomBar.onReset = { [weak self] in self?.resetZoom() }
        nativeZoomBar.onToggleTheme = { [weak self] in self?.toggleTheme() }
        nativeZoomBar.frame.origin = NSPoint(x: 16, y: 12)
        nativeZoomBar.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(nativeZoomBar)

        // Logo (top left, non-interactive)
        let logo = NSTextField(labelWithString: ">_ floaterm")
        logo.font = .systemFont(ofSize: 14, weight: .semibold)
        logo.textColor = .secondaryLabelColor
        logo.alphaValue = 0.7
        logo.frame = NSRect(x: 16, y: wH - 38, width: 120, height: 24)
        logo.autoresizingMask = [.maxXMargin, .minYMargin]
        contentView.addSubview(logo)

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

        // Update UI counts
        nativeTermListBtn.updateCount(appState.boxes.count)
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
        nativeZoomBar?.updateZoom(appState.transform.scale)
        nativeTermListBtn?.updateCount(appState.boxes.count)
        nativeToolbar?.updateSelection()
    }

    private func frameForBox(_ box: TerminalBox) -> NSRect {
        let screen = appState.transform.worldToScreen(wx: box.x, wy: box.y)
        // In unflipped coords, Y is from bottom. World Y increases downward.
        // So screen.y needs to be flipped: windowHeight - screen.y - scaledHeight
        let windowHeight = window.contentView?.bounds.height ?? Dimensions.defaultWindowHeight
        let scaledH = box.h * appState.transform.scale
        return NSRect(x: screen.x, y: windowHeight - screen.y - scaledH, width: box.w, height: box.h)
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

// MARK: - Helper views

/// An NSView that passes through mouse events when no child is hit
private class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

