import SwiftUI

struct ContentView: View {
    private let appModel: AppModel
    @ObservedObject private var store: CanvasStore
    @ObservedObject private var settings: AppSettingsStore
    @State private var isShowingSettings = false

    init(appModel: AppModel = .shared) {
        self.appModel = appModel
        _store = ObservedObject(wrappedValue: appModel.store)
        _settings = ObservedObject(wrappedValue: appModel.settings)
    }

    var body: some View {
        ZStack {
            CanvasViewRepresentable(store: store, appModel: appModel)
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
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.seedInitialNodeIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolSection
            separator
            zoomSection

            if store.selectionCount > 0 {
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
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
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
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
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
                        .foregroundStyle(store.tool == tool ? Color.black : Color.primary)
                        .background(
                            Capsule()
                                .fill(store.tool == tool ? Color.white : Color.white.opacity(0.06))
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
                .foregroundStyle(Color(red: 0.98, green: 0.53, blue: 0.50))
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help("Delete the current selection")
    }

    private var selectionBadge: some View {
        Text("\(store.selectionCount) selected")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
            )
    }

    private var separator: some View {
        Capsule()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 30)
    }

    private func toolbarIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.06))
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
        case .text:
            return "Click anywhere to place text."
        }
    }
}
