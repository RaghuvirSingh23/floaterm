import Foundation

@MainActor
final class PTYManager {
    private var sessions: [String: PTYSession] = [:]

    func getOrCreate(id: String, cols: Int, rows: Int, command: String? = nil) -> PTYSession {
        if let existing = sessions[id], existing.alive {
            return existing
        }
        // Clean up dead session
        sessions.removeValue(forKey: id)

        let session = PTYSession(cols: cols, rows: rows, command: command)
        sessions[id] = session
        return session
    }

    func destroy(id: String) {
        sessions[id]?.kill()
        sessions.removeValue(forKey: id)
    }

    func session(for id: String) -> PTYSession? {
        guard let s = sessions[id], s.alive else { return nil }
        return s
    }

    func allSessionIds() -> [String] {
        sessions.filter { $0.value.alive }.map(\.key)
    }

    func cleanup() {
        for (_, session) in sessions {
            session.kill()
        }
        sessions.removeAll()
    }
}
