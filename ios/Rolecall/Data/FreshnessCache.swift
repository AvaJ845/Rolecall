import Foundation

/// In-memory, per-process cache of on-device liveness results, keyed by role URL.
/// The caller passes a TTL (≈15 min); entries past it are evicted on read. LRU-capped so
/// a long browsing session can't grow it without bound. Nothing is persisted — a
/// relaunch re-checks from scratch.
actor FreshnessCache {

    static let shared = FreshnessCache()

    private struct Entry {
        let status: FreshnessChecker.Status
        let at: Date
    }

    private let capacity: Int
    private let clock: @Sendable () -> Date
    private var entries: [String: Entry] = [:]
    private var order: [String] = []   // LRU: least-recent first, most-recent last

    init(capacity: Int = 200, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.capacity = max(1, capacity)
        self.clock = clock
    }

    /// The cached status for `url` if it is younger than `ttl`, else nil (and evicted).
    func value(for url: URL, ttl: TimeInterval) -> FreshnessChecker.Status? {
        let key = url.absoluteString
        guard let entry = entries[key] else { return nil }
        guard clock().timeIntervalSince(entry.at) < ttl else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.status
    }

    func store(_ status: FreshnessChecker.Status, for url: URL) {
        let key = url.absoluteString
        entries[key] = Entry(status: status, at: clock())
        touch(key)
        while order.count > capacity {
            remove(order[0])
        }
    }

    func reset() {
        entries.removeAll()
        order.removeAll()
    }

    var count: Int { entries.count }

    private func touch(_ key: String) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }

    private func remove(_ key: String) {
        entries[key] = nil
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
    }
}
