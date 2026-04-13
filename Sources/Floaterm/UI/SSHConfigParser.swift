import Foundation

struct SSHHost: Identifiable {
    let id = UUID()
    let name: String
}

struct SSHConfigParser {
    static func parse() -> [SSHHost] {
        let path = NSHomeDirectory() + "/.ssh/config"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }

        var hosts: [SSHHost] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("host ") else { continue }
            let name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            // Skip wildcards
            guard !name.contains("*"), !name.contains("?"), !name.isEmpty else { continue }
            hosts.append(SSHHost(name: name))
        }
        return hosts
    }
}
