import AppKit

/// Pure AppKit toolbar — no SwiftUI, no hitTest hell
final class NativeToolbarView: NSView {
    var appState: AppState!
    var onSpawnCenter: (() -> Void)?
    private var buttons: [Tool: NSButton] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow?.shadowOffset = NSSize(width: 0, height: -2)
        shadow?.shadowBlurRadius = 4
    }

    required init?(coder: NSCoder) { fatalError() }

    func setup(appState: AppState, onSpawnCenter: @escaping () -> Void) {
        self.appState = appState
        self.onSpawnCenter = onSpawnCenter

        let tools: [(Tool, String)] = [
            (.draw, "square.dashed"),
            (.hand, "hand.raised"),
        ]
        let separator1 = makeSeparator()
        let spawnTools: [(Tool, String)] = [
            (.spawn, "plus.rectangle"),
        ]
        let separator2 = makeSeparator()
        let shapeTools: [(Tool, String)] = [
            (.shapeRect, "rectangle"),
            (.shapeCircle, "circle"),
            (.shapeArrow, "arrow.right"),
            (.shapeText, "textformat"),
            (.shapeFreehand, "scribble"),
        ]

        var x: CGFloat = 4
        for (tool, icon) in tools {
            let btn = makeButton(icon: icon, tool: tool)
            btn.frame.origin = NSPoint(x: x, y: 4)
            addSubview(btn)
            buttons[tool] = btn
            x += 32
        }
        separator1.frame.origin = NSPoint(x: x + 2, y: 8)
        addSubview(separator1)
        x += 6

        for (tool, icon) in spawnTools {
            let btn = makeButton(icon: icon, tool: tool)
            btn.frame.origin = NSPoint(x: x, y: 4)
            addSubview(btn)
            buttons[tool] = btn
            x += 32
        }
        separator2.frame.origin = NSPoint(x: x + 2, y: 8)
        addSubview(separator2)
        x += 6

        for (tool, icon) in shapeTools {
            let btn = makeButton(icon: icon, tool: tool)
            btn.frame.origin = NSPoint(x: x, y: 4)
            addSubview(btn)
            buttons[tool] = btn
            x += 32
        }

        frame.size = NSSize(width: x + 4, height: 36)
        updateSelection()
    }

    private func makeButton(icon: String, tool: Tool) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: tool.rawValue)
        btn.imageScaling = .scaleProportionallyDown
        btn.isBordered = false
        btn.bezelStyle = .recessed
        btn.setButtonType(.momentaryPushIn)
        btn.target = self
        btn.action = #selector(toolClicked(_:))
        btn.tag = Tool.allCases.firstIndex(of: tool) ?? 0
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    private func makeSeparator() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 20))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return v
    }

    @objc private func toolClicked(_ sender: NSButton) {
        let tool = Tool.allCases[sender.tag]
        if tool == .spawn {
            onSpawnCenter?()
        } else {
            appState.activeTool = tool
            updateSelection()
        }
    }

    func updateSelection() {
        for (tool, btn) in buttons {
            if tool == appState.activeTool {
                btn.contentTintColor = .controlAccentColor
                btn.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            } else {
                btn.contentTintColor = .secondaryLabelColor
                btn.layer?.backgroundColor = .clear
            }
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
        }
    }
}

/// Pure AppKit quick spawn button
final class NativeQuickSpawnButton: NSButton {
    var onSpawnCommand: ((String, String) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: 28))
        title = "+ New"
        bezelStyle = .rounded
        isBordered = true
        contentTintColor = .white
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x1F883D).cgColor
        layer?.cornerRadius = 8
        font = .systemFont(ofSize: 13)
        target = self
        action = #selector(clicked)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Claude Code", action: #selector(spawnClaude), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Codex", action: #selector(spawnCodex), keyEquivalent: "").target = self
        menu.addItem(.separator())

        // SSH hosts
        let hosts = SSHConfigParser.parse()
        if hosts.isEmpty {
            let item = menu.addItem(withTitle: "No SSH hosts", action: nil, keyEquivalent: "")
            item.isEnabled = false
        } else {
            for host in hosts {
                let item = menu.addItem(withTitle: host.name, action: #selector(spawnSSH(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = host.name
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
    }

    @objc private func spawnClaude() { onSpawnCommand?("claude", "claude") }
    @objc private func spawnCodex() { onSpawnCommand?("codex", "codex") }
    @objc private func spawnSSH(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        onSpawnCommand?(name, "ssh \(name)")
    }
}

/// Pure AppKit zoom bar
final class NativeZoomBar: NSView {
    var appState: AppState!
    var onReset: (() -> Void)?
    var onToggleTheme: (() -> Void)?
    private var zoomLabel: NSTextField!

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 27))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        zoomLabel = NSTextField(labelWithString: "100%")
        zoomLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.frame = NSRect(x: 6, y: 4, width: 44, height: 18)
        addSubview(zoomLabel)

        let resetBtn = NSButton(frame: NSRect(x: 52, y: 2, width: 24, height: 22))
        resetBtn.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")
        resetBtn.imageScaling = .scaleProportionallyDown
        resetBtn.isBordered = false
        resetBtn.target = self
        resetBtn.action = #selector(resetClicked)
        addSubview(resetBtn)

        let sep = NSView(frame: NSRect(x: 80, y: 4, width: 1, height: 18))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(sep)

        let themeBtn = NSButton(frame: NSRect(x: 86, y: 2, width: 24, height: 22))
        themeBtn.image = NSImage(systemSymbolName: "moon", accessibilityDescription: "Theme")
        themeBtn.imageScaling = .scaleProportionallyDown
        themeBtn.isBordered = false
        themeBtn.target = self
        themeBtn.action = #selector(themeClicked)
        addSubview(themeBtn)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateZoom(_ scale: CGFloat) {
        zoomLabel.stringValue = "\(Int(scale * 100))%"
    }

    @objc private func resetClicked() { onReset?() }
    @objc private func themeClicked() { onToggleTheme?() }
}

/// Pure AppKit terminal list button
final class NativeTerminalListButton: NSButton {
    var appState: AppState!
    var onFocus: ((String) -> Void)?
    var onClose: ((String) -> Void)?
    private var countLabel: NSTextField!

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 60, height: 28))
        image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Terminals")
        imageScaling = .scaleProportionallyDown
        isBordered = true
        bezelStyle = .rounded
        target = self
        action = #selector(clicked)

        countLabel = NSTextField(labelWithString: "0")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.frame = NSRect(x: 34, y: 6, width: 20, height: 16)
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateCount(_ count: Int) {
        countLabel.stringValue = "\(count)"
    }

    @objc private func clicked() {
        guard let appState else { return }
        let menu = NSMenu()
        if appState.boxes.isEmpty {
            let item = menu.addItem(withTitle: "No terminals", action: nil, keyEquivalent: "")
            item.isEnabled = false
        } else {
            for box in appState.boxes {
                let item = menu.addItem(withTitle: box.label, action: #selector(focusTerminal(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = box.id

                // Close sub-item
                let closeItem = NSMenuItem(title: "Close \(box.label)", action: #selector(closeTerminal(_:)), keyEquivalent: "")
                closeItem.target = self
                closeItem.representedObject = box.id
                item.submenu = NSMenu()
                item.submenu?.addItem(closeItem)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
    }

    @objc private func focusTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onFocus?(id)
    }

    @objc private func closeTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onClose?(id)
    }
}
