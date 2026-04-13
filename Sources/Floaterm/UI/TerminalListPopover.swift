import SwiftUI

struct TerminalListPopover: View {
    @ObservedObject var appState: AppState
    var onFocus: (String) -> Void
    var onClose: (String) -> Void
    var onRename: (String, String) -> Void
    @State private var showList = false

    var body: some View {
        Button {
            showList.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13))
                Text("\(appState.boxes.count)")
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showList, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(appState.boxes) { box in
                    TerminalListItem(
                        box: box,
                        onFocus: { onFocus(box.id); showList = false },
                        onClose: { onClose(box.id) },
                        onRename: { newLabel in onRename(box.id, newLabel) }
                    )
                }
                if appState.boxes.isEmpty {
                    Text("No terminals")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
            .frame(width: 220)
            .padding(.vertical, 4)
        }
    }
}

private struct TerminalListItem: View {
    let box: TerminalBox
    var onFocus: () -> Void
    var onClose: () -> Void
    var onRename: (String) -> Void
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)

            if isEditing {
                TextField("", text: $editText, onCommit: {
                    if !editText.isEmpty { onRename(editText) }
                    isEditing = false
                })
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
            } else {
                Text(box.label)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onFocus() }
            }

            Spacer()

            Button { editText = box.label; isEditing = true } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(0.6)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(box.focused ? Color.green.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
