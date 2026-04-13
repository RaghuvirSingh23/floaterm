import SwiftUI

struct ZoomBar: View {
    @ObservedObject var appState: AppState
    var onReset: () -> Void
    var onToggleTheme: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(Int(appState.transform.scale * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36)

            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(ZoomBarButtonStyle())
            .help("Reset zoom and position")

            Divider().frame(height: 20)

            Button(action: onToggleTheme) {
                Image(systemName: appState.theme == .dark ? "sun.max" : "moon")
                    .font(.system(size: 12))
            }
            .buttonStyle(ZoomBarButtonStyle())
            .help("Toggle dark mode")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
    }
}

private struct ZoomBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .padding(3)
            .background(configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
