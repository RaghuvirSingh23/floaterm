import SwiftUI

struct ToolbarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            toolButton(tool: .draw, icon: "square.dashed", tooltip: "Draw terminal (D)")
            toolButton(tool: .hand, icon: "hand.raised", tooltip: "Hand tool (H)")
            Divider().frame(height: 20)
            toolButton(tool: .spawn, icon: "plus.rectangle", tooltip: "New terminal")
            Divider().frame(height: 20)
            toolButton(tool: .shapeRect, icon: "rectangle", tooltip: "Rectangle")
            toolButton(tool: .shapeCircle, icon: "circle", tooltip: "Circle")
            toolButton(tool: .shapeArrow, icon: "arrow.right", tooltip: "Arrow")
            toolButton(tool: .shapeText, icon: "textformat", tooltip: "Text")
            toolButton(tool: .shapeFreehand, icon: "scribble", tooltip: "Freehand")
        }
        .padding(4)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .contentShape(Rectangle())
    }

    private func toolButton(tool: Tool, icon: String, tooltip: String) -> some View {
        Button {
            appState.activeTool = tool
        } label: {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .foregroundStyle(appState.activeTool == tool ? Color.accentColor : Color.secondary)
                .background(appState.activeTool == tool ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
        .help(tooltip)
    }
}
