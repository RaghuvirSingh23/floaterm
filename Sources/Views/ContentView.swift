import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let appModel: AppModel
    @ObservedObject private var store: CanvasStore
    @ObservedObject private var settings: AppSettingsStore
    @State private var isShowingSettings = false
    @State private var isMinimapExpanded = false
    @State private var minimapCollapseTask: Task<Void, Never>?

    init(appModel: AppModel = .shared) {
        self.appModel = appModel
        _store = ObservedObject(wrappedValue: appModel.store)
        _settings = ObservedObject(wrappedValue: appModel.settings)
    }

    var body: some View {
        ZStack {
            CanvasViewRepresentable(store: store, appModel: appModel, appearanceMode: settings.appAppearanceMode)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar
                    .padding(.top, 16)

                Spacer()
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    settingsButton
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                HStack {
                    Spacer()
                    CanvasMinimapView(store: store, theme: theme, isExpanded: isMinimapExpanded)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }

            WindowAppearanceView(mode: settings.appAppearanceMode)
                .frame(width: 0, height: 0)
        }
        .preferredColorScheme(settings.appAppearanceMode.preferredColorScheme)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.seedInitialNodeIfNeeded()
        }
        .onChange(of: store.minimapActivityTick) { _, _ in
            pulseMinimap()
        }
    }

    private var theme: FloatermTheme {
        FloatermTheme(colorScheme: colorScheme)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolSection
            separator
            zoomSection

            if store.selectionCount > 0 {
                if store.canBroadcastSelectedTerminals {
                    separator
                    broadcastSection
                }

                if store.canWrapSelectionInFrame {
                    separator
                    frameSection
                }

                separator
                deleteSection
                selectionBadge
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color(nsColor: theme.toolbarBorder), lineWidth: 1)
        )
        .shadow(color: Color(nsColor: theme.toolbarShadow), radius: 18, x: 0, y: 10)
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color(nsColor: theme.toolbarBorder), lineWidth: 1)
                )
                .foregroundStyle(Color(nsColor: theme.toolbarPrimaryText))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingSettings, arrowEdge: .top) {
            settingsPopover
        }
        .help("Terminal persistence settings")
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))

            Text("Appearance")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Appearance", selection: $settings.appAppearanceMode) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Terminal Persistence")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Terminal Persistence", selection: $settings.terminalPersistenceMode) {
                ForEach(TerminalPersistenceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.terminalPersistenceMode.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var toolSection: some View {
        HStack(spacing: 6) {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    store.tool = tool
                } label: {
                    Label(tool.title, systemImage: tool.symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(store.tool == tool ? Color(nsColor: theme.toolbarSelectedText) : Color(nsColor: theme.toolbarPrimaryText))
                        .background(
                            Capsule()
                                .fill(store.tool == tool ? Color(nsColor: theme.toolbarSelectedFill) : Color(nsColor: theme.toolbarControlFill))
                        )
                }
                .buttonStyle(.plain)
                .help(toolHelpText(for: tool))
            }
        }
    }

    private var zoomSection: some View {
        HStack(spacing: 6) {
            toolbarIconButton(systemName: "minus") {
                store.zoom(by: 1 / 1.12, around: CGPoint(x: store.viewportSize.width * 0.5, y: store.viewportSize.height * 0.5))
            }

            Text("\(Int(store.camera.zoom * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(minWidth: 52)

            toolbarIconButton(systemName: "plus") {
                store.zoom(by: 1.12, around: CGPoint(x: store.viewportSize.width * 0.5, y: store.viewportSize.height * 0.5))
            }

            Button {
                store.resetZoom()
            } label: {
                Text("100%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: theme.toolbarControlFill))
                    )
            }
            .buttonStyle(.plain)
            .help("Reset zoom to 100% and center on the current selection or canvas content")
        }
    }

    private var deleteSection: some View {
        Button {
            store.deleteSelection()
        } label: {
            Label("Delete", systemImage: "trash")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(Color(nsColor: theme.toolbarDeleteText))
                .background(
                    Capsule()
                        .fill(Color(nsColor: theme.toolbarDeleteFill))
                )
        }
        .buttonStyle(.plain)
        .help("Delete the current selection")
    }

    private var broadcastSection: some View {
        Button {
            store.setTerminalBroadcastEnabled(!store.isTerminalBroadcastEnabled)
            if store.isTerminalBroadcastEnabled {
                store.requestFocusOnSelectedTerminal()
            }
        } label: {
            Label("Broadcast", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(
                    store.isTerminalBroadcastEnabled
                        ? Color(nsColor: theme.toolbarBroadcastEnabledText)
                        : Color(nsColor: theme.toolbarBroadcastText)
                )
                .background(
                    Capsule()
                        .fill(
                            store.isTerminalBroadcastEnabled
                                ? Color(nsColor: theme.toolbarBroadcastEnabledFill)
                                : Color(nsColor: theme.toolbarBroadcastFill)
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Mirror typed input from one selected terminal to the others")
    }

    private var frameSection: some View {
        Button {
            _ = store.wrapSelectionInFrame()
        } label: {
            Label("Frame", systemImage: "square.on.square.dashed")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(Color(nsColor: theme.toolbarFrameText))
                .background(
                    Capsule()
                        .fill(Color(nsColor: theme.toolbarFrameFill))
                )
        }
        .buttonStyle(.plain)
        .help("Wrap the current selection in a frame")
    }

    private var selectionBadge: some View {
        Text("\(store.selectionCount) selected")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(nsColor: theme.toolbarSecondaryText))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: theme.selectionBadgeFill))
            )
    }

    private var separator: some View {
        Capsule()
            .fill(Color(nsColor: theme.toolbarDivider))
            .frame(width: 1, height: 30)
    }

    private func toolbarIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(Color(nsColor: theme.toolbarPrimaryText))
                .background(
                    Circle()
                        .fill(Color(nsColor: theme.toolbarControlFill))
                )
        }
        .buttonStyle(.plain)
    }

    private func toolHelpText(for tool: CanvasTool) -> String {
        switch tool {
        case .select:
            return "Select items. Drag on empty canvas to marquee-select."
        case .terminal:
            return "Drag to create a terminal."
        case .frame:
            return "Drag to create a frame."
        case .text:
            return "Click anywhere to place text."
        }
    }

    private func pulseMinimap() {
        minimapCollapseTask?.cancel()

        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            isMinimapExpanded = true
        }

        minimapCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.90)) {
                isMinimapExpanded = false
            }
        }
    }
}

private struct WindowAppearanceView: NSViewRepresentable {
    let mode: AppAppearanceMode

    func makeNSView(context: Context) -> WindowAppearanceHostView {
        let view = WindowAppearanceHostView()
        view.mode = mode
        return view
    }

    func updateNSView(_ nsView: WindowAppearanceHostView, context: Context) {
        nsView.mode = mode
    }
}

private final class WindowAppearanceHostView: NSView {
    var mode: AppAppearanceMode = .dark {
        didSet {
            guard mode != oldValue else {
                return
            }

            applyAppearance()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    private func applyAppearance() {
        window?.appearance = mode.nsAppearance
    }
}
