import Foundation

struct IdAllocator {
    /// Returns the lowest available terminal ID like "t1", "t2", etc.
    /// given a set of existing IDs.
    static func lowestAvailable(existing: [String]) -> String {
        let used: Set<Int> = Set(existing.compactMap { id in
            guard id.hasPrefix("t"), let n = Int(id.dropFirst()) else { return nil }
            return n
        })
        var i = 1
        while used.contains(i) { i += 1 }
        return "t\(i)"
    }
}
