import SwiftUI

struct QuickSpawnMenu: View {
    @ObservedObject var appState: AppState
    var onSpawn: (String, String) -> Void
    @State private var showMenu = false
    @State private var sshHosts: [SSHHost] = []

    var body: some View {
        Button {
            showMenu.toggle()
            if showMenu { sshHosts = SSHConfigParser.parse() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("New")
                    .font(.system(size: 13))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(hex: 0x1F883D)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Tools")
                menuItem(icon: "terminal", label: "Claude Code") { onSpawn("claude", "claude"); showMenu = false }
                menuItem(icon: "terminal", label: "Codex") { onSpawn("codex", "codex"); showMenu = false }

                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                sectionLabel("SSH Hosts")

                if sshHosts.isEmpty {
                    Text("No hosts found")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else {
                    ForEach(sshHosts) { host in
                        menuItem(icon: "network", label: host.name) {
                            onSpawn(host.name, "ssh \(host.name)")
                            showMenu = false
                        }
                    }
                }
            }
            .frame(width: 200)
            .padding(.vertical, 4)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 3)
    }

    private func menuItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
