import AppKit
import SwiftTerm

final class TerminalBoxView: NSView {
    let boxId: String
    var terminalView: TerminalView!
    var ptySession: PTYSession?
    private var titleBar: TitleBarView!
    private var labelField: NSTextField!
    private var closeButton: NSButton!
    private var resizeHandles: [String: ResizeHandleView] = [:]

    var onDragStart: ((String, NSPoint) -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    var onResizeStart: ((String, String, NSEvent) -> Void)?
    var onResizeMoved: ((NSEvent) -> Void)?
    var onResizeEnded: ((NSEvent) -> Void)?
    var onFocus: ((String) -> Void)?
    var onClose: ((String) -> Void)?
    var onLabelChanged: ((String, String) -> Void)?

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
        titleBar = TitleBarView()
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = Colors.titleBarBg.cgColor
        addSubview(titleBar)

        labelField = NSTextField(string: label)
        labelField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.textColor = Colors.titleBarText
        labelField.backgroundColor = .clear
        labelField.drawsBackground = false
        labelField.isBordered = false
        labelField.isEditable = false
        labelField.isSelectable = false
        labelField.focusRingType = .none
        labelField.lineBreakMode = .byTruncatingTail
        labelField.delegate = self
        titleBar.addSubview(labelField)

        closeButton = NSButton(title: "\u{2715}", target: self, action: #selector(closeTapped))
        closeButton.isBordered = false
        closeButton.font = NSFont.systemFont(ofSize: 14)
        closeButton.contentTintColor = Colors.titleBarText
        closeButton.alphaValue = 0.5
        titleBar.addSubview(closeButton)

        // Title bar drag/double-click
        titleBar.onDragStart = { [weak self] event in
            guard let self else { return }
            self.onFocus?(self.boxId)
            self.onDragStart?(self.boxId, event.locationInWindow)
        }
        titleBar.onDragMoved = { [weak self] event in
            self?.onDragMoved?(event)
        }
        titleBar.onDragEnded = { [weak self] event in
            self?.onDragEnded?(event)
        }
        titleBar.onDoubleClick = { [weak self] in
            self?.startEditingLabel()
        }
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
            view.onDragStart = { [weak self] event in
                guard let self else { return }
                self.onResizeStart?(self.boxId, handle, event)
            }
            view.onDragMoved = { [weak self] event in
                self?.onResizeMoved?(event)
            }
            view.onDragEnded = { [weak self] event in
                self?.onResizeEnded?(event)
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
        labelField.frame = NSRect(x: 8, y: 2, width: b.width - 40, height: th - 4)
        closeButton.frame = NSRect(x: b.width - 24, y: 2, width: 20, height: 20)

        terminalView.frame = NSRect(x: 0, y: th, width: b.width, height: b.height - th)

        // Resize handles
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

        if !session.scrollback.isEmpty, let data = session.scrollback.data(using: .utf8) {
            terminalView.feed(byteArray: ArraySlice(data))
        }

        session.onOutput = { [weak self] data in
            self?.terminalView.feed(byteArray: ArraySlice(data))
        }

        terminalView.terminalDelegate = self
    }

    func updateCols() -> (cols: Int, rows: Int) {
        let fontSize: CGFloat = 14
        let cellWidth: CGFloat = fontSize * 0.6
        let cellHeight: CGFloat = fontSize * 1.2
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

    // MARK: - Mouse — click on terminal body focuses

    override func mouseDown(with event: NSEvent) {
        onFocus?(boxId)
        // Let SwiftTerm handle clicks in the terminal area
        super.mouseDown(with: event)
    }

    // MARK: - Label editing

    private func startEditingLabel() {
        labelField.isEditable = true
        labelField.isSelectable = true
        labelField.textColor = .white
        labelField.backgroundColor = NSColor(white: 0.2, alpha: 1)
        labelField.drawsBackground = true
        window?.makeFirstResponder(labelField)
        labelField.selectText(nil)
    }

    private func finishEditingLabel() {
        labelField.isEditable = false
        labelField.isSelectable = false
        labelField.textColor = Colors.titleBarText
        labelField.drawsBackground = false
        let text = labelField.stringValue.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            onLabelChanged?(boxId, text)
        }
        window?.makeFirstResponder(terminalView)
    }

    @objc private func closeTapped() {
        onClose?(boxId)
    }

    func updateLabel(_ text: String) {
        labelField.stringValue = text
    }
}

// MARK: - NSTextFieldDelegate

extension TerminalBoxView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        finishEditingLabel()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditingLabel()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            labelField.abortEditing()
            finishEditingLabel()
            return true
        }
        return false
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

// MARK: - Title bar view (handles drag separately from SwiftTerm)

private class TitleBarView: NSView {
    override var isFlipped: Bool { true }
    var onDragStart: ((NSEvent) -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    private var isDragging = false

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            isDragging = true
            onDragStart?(event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            onDragMoved?(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onDragEnded?(event)
        }
    }
}

// MARK: - Resize handle view (handles its own drag lifecycle)

private class ResizeHandleView: NSView {
    let direction: String
    var cursor: NSCursor = .arrow
    var onDragStart: ((NSEvent) -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: ((NSEvent) -> Void)?
    private var isDragging = false

    init(direction: String) {
        self.direction = direction
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        onDragStart?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isDragging { onDragMoved?(event) }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onDragEnded?(event)
        }
    }
}
