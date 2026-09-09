import Foundation

/// The one file the app and the widget both read: the merged board snapshot, written to
/// the App Group container by the app after every load/refresh.
///
/// Everything here is device-local. Nothing is transmitted; no network request varies
/// with anything stored here. Keys are product-name-free so a rename never forces a data
/// migration.
enum SharedContainer {

    static let appGroupID = "group.com.avaresearch.rolecall"

    /// App Group defaults when the entitlement is honoured; otherwise the process
    /// defaults, so the app still works on a simulator that has not been signed.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Last-known Plus entitlement, written by `Store.refreshEntitlements()` every time it
    /// runs. The background-refresh task reads this plain Bool instead of spinning up the
    /// whole StoreKit stack: worst case a lapsed subscriber gets one extra alert cycle, or
    /// a brand-new one waits a cycle. Defaults to `false` before the app has run.
    private static let lastKnownIsPlusKey = "entitlement.plus.lastKnown"

    static var lastKnownIsPlus: Bool {
        get { defaults.bool(forKey: lastKnownIsPlusKey) }
        set { defaults.set(newValue, forKey: lastKnownIsPlusKey) }
    }

    /// Shared board snapshot, written by the app for the widget to read.
    static var boardFile: URL? {
        directory?.appendingPathComponent("board.json")
    }

    /// Process-local fallback for when the App Group container is unavailable
    /// (unsigned simulator builds).
    static var localBoardFile: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("board.json")
    }

    /// Write the merged board where the widget can find it. Best-effort and atomic.
    ///
    /// One write, not two: when the App Group container is available (every provisioned
    /// build) that is the single source of truth. The Application Support copy is only a
    /// fallback for an unsigned simulator that has no container at all.
    static func writeBoard(_ board: Board) {
        guard let data = try? board.encoded() else { return }
        if let shared = boardFile {
            try? data.write(to: shared, options: .atomic)
        } else {
            try? data.write(to: localBoardFile, options: .atomic)
        }
    }

    /// The board as last written by the app, for headless code (the widget timeline).
    /// Returns `nil` before the app has ever run.
    static func currentBoard() -> Board? {
        for url in [boardFile, Optional(localBoardFile)].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let board = try? Board.decode(from: data)
            else { continue }
            return board
        }
        return nil
    }
}
