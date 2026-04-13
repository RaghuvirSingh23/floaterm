import AppKit
import SwiftTerm

final class TerminalBoxView: NSView {
    let boxId: String
    var terminalView: TerminalView!
    var ptySession: PTYSession?
    private var titleBar: NSView!
    private var labelField: NSTextField!
    private var closeButton: NSButton!
    private var resizeHandles: [String: NSView] = [:]

    var onDragStart: ((String, CGPoint) -> Void)?
    var onResizeStart: ((String, String, CGPoint) -> Void)?
    var onFocus: ((String) -> Void)?
    var onClose: ((String) -> Void)?
    var onLabelChanged: ((String, String) -> Void)?
    var onResizeEnd: ((String, Int, Int) -> Void)?

    override var isFlipped: Bool { true }

    init(box: TerminalBox) {
        self.boxId = box.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Colors.terminalBg.cgColor
        layer?.borderColor = Colors.terminalBorder.cgColor
        layer?.borderWidth = 2
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        setupTitleBar(label: box.label)
        setupTerminalView()
        setupResizeHandles()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupTitleBar(label: String) {
        titleBar = NSView()
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = Colors.titleBarBg.cgColor
        addSubview(titleBar)

        labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.textColor = Colors.titleBarText
        labelField.backgroundColor = .clear
        labelField.isBordered = false
        labelField.isEditable = false
        labelField.lineBreakMode = .byTruncatingTail
        titleBar.addSubview(labelField)

        closeButton = NSButton(title: "\u{2715}", target: self, action: #selector(closeTapped))
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 14)
        closeButton.contentTintColor = Colors.titleBarText
        closeButton.alphaValue = 0.5
        titleBar.addSubview(closeButton)
    }

    private func setupTerminalView() {
        terminalView = TerminalView(frame: .zero)
        terminalView.configureNativeColors()
        addSubview(terminalView)
    }

    private func setupResizeHandles() {
        let handles = ["n", "s", "e", "w", "nw", "ne", "sw", "se"]
        let cursors: [String: NSCursor] = [
            "n": .resizeUpDown, "s": .resizeUpDown,
            "e": .resizeLeftRight, "w": .resizeLeftRight,
            "nw": .crosshair, "ne": .crosshair,
            "sw": .crosshair, "se": .crosshair,
        ]

        for handle in handles {
            let view = ResizeHandleView(direction: handle)
            view.cursor = cursors[handle] ?? .arrow
            view.onMouseDown = { [weak self] point in
                guard let self else { return }
                self.onResizeStart?(self.boxId, handle, self.convert(point, to: nil))
            }
            addSubview(view)
            resizeHandles[handle] = view
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let b = bounds
        let th = Dimensions.titleBarHeight

        titleBar.frame = NSRect(x: 0, y: 0, width: b.width, height: th)
        labelField.frame = NSRect(x: 8, y: 0, width: b.width - 40, height: th)
        closeButton.frame = NSRect(x: b.width - 24, y: 2, width: 20, height: 20)

        terminalView.frame = NSRect(x: 0, y: th, width: b.width, height: b.height - th)

        // Position resize handles
        let hs = Dimensions.resizeHandleSize
        let cs = Dimensions.cornerHandleSize
        resizeHandles["n"]?.frame = NSRect(x: 10, y: -3, width: b.width - 20, height: hs)
        resizeHandles["s"]?.frame = NSRect(x: 10, y: b.height - 3, width: b.width - 20, height: hs)
        resizeHandles["e"]?.frame = NSRect(x: b.width - 3, y: 10, width: hs, height: b.height - 20)
        resizeHandles["w"]?.frame = NSRect(x: -3, y: 10, width: hs, height: b.height - 20)
        resizeHandles["nw"]?.frame = NSRect(x: -4, y: -4, width: cs, height: cs)
        resizeHandles["ne"]?.frame = NSRect(x: b.width - cs + 4, y: -4, width: cs, height: cs)
        resizeHandles["sw"]?.frame = NSRect(x: -4, y: b.height - cs + 4, width: cs, height: cs)
        resizeHandles["se"]?.frame = NSRect(x: b.width - cs + 4, y: b.height - cs + 4, width: cs, height: cs)
    }

    // MARK: - PTY connection

    func connectPTY(_ session: PTYSession) {
        self.ptySession = session

        // Feed existing scrollback
        if !session.scrollback.isEmpty, let data = session.scrollback.data(using: .utf8) {
            terminalView.feed(byteArray: ArraySlice(data))
        }

        // Wire PTY output to terminal view
        session.onOutput = { [weak self] data in
            self?.terminalView.feed(byteArray: ArraySlice(data))
        }

        // Wire terminal input to PTY
        terminalView.terminalDelegate = self
    }

    func updateCols() -> (cols: Int, rows: Int) {
        // Estimate based on font metrics — SwiftTerm uses a monospaced font
        let fontSize: CGFloat = 14
        let cellWidth: CGFloat = fontSize * 0.6  // approximate monospace char width
        let cellHeight: CGFloat = fontSize * 1.2 // approximate line height
        let contentHeight = bounds.height - Dimensions.titleBarHeight
        let cols = max(1, Int(bounds.width / cellWidth))
        let rows = max(1, Int(contentHeight / cellHeight))
        return (cols, rows)
    }

    // MARK: - Focus

    func setFocused(_ focused: Bool) {
        layer?.borderColor = focused ? Colors.focusBorder.cgColor : Colors.terminalBorder.cgColor
        if focused {
            window?.makeFirstResponder(terminalView)
        }
    }

    // MARK: - Title bar drag

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.y < Dimensions.titleBarHeight {
            onFocus?(boxId)
            onDragStart?(boxId, event.locationInWindow)
        } else {
            onFocus?(boxId)
            super.mouseDown(with: event)
        }
    }

    @objc private func closeTapped() {
        onClose?(boxId)
    }

    func updateLabel(_ text: String) {
        labelField.stringValue = text
    }
}

// MARK: - TerminalViewDelegate

extension TerminalBoxView: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        ptySession?.write(Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(content, forType: .string)
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

// MARK: - Resize handle view

private class ResizeHandleView: NSView {
    let direction: String
    var cursor: NSCursor = .arrow
    var onMouseDown: ((CGPoint) -> Void)?

    init(direction: String) {
        self.direction = direction
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
    }
}
