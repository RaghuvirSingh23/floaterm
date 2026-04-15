import SwiftUI

struct ContentView: View {
    @StateObject private var store = CanvasStore()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CanvasViewRepresentable(store: store)
                .ignoresSafeArea()

            instructionCard
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            zoomHUD
                .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Picker("Tool", selection: $store.tool) {
                    ForEach(CanvasTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.symbolName)
                            .tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Button {
                    store.spawnPresetTerminal()
                } label: {
                    Label("Quick Terminal", systemImage: "plus.rectangle.on.rectangle")
                }
                .help("Spawn a terminal at the center of the current viewport")
            }
        }
        .onAppear {
            store.seedInitialNodeIfNeeded()
        }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.tool == .terminal ? "Drag to size a new terminal" : "Space-drag or scroll to move the canvas")
                .font(.headline)

            Text("Pinch to zoom. Drag a terminal header to move it. Pull edges or corners to resize. Click the red close button to kill a terminal.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                pill("T", "terminal tool")
                pill("V", "select tool")
                pill("+ / -", "zoom")
                pill("delete", "close selected")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
    }

    private var zoomHUD: some View {
        HStack(spacing: 10) {
            Button {
                store.zoom(by: 1 / 1.12, around: CGPoint(x: store.viewportSize.width * 0.5, y: store.viewportSize.height * 0.5))
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderedProminent)

            Text("\(Int(store.camera.zoom * 100))%")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .frame(minWidth: 56)

            Button {
                store.zoom(by: 1.12, around: CGPoint(x: store.viewportSize.width * 0.5, y: store.viewportSize.height * 0.5))
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button("Reset") {
                store.resetZoom()
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
    }

    private func pill(_ key: String, _ description: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
