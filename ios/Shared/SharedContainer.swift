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
    static func writeBoard(_ board: Board) {
        guard let data = try? board.encoded() else { return }
        let targets = [boardFile, Optional(localBoardFile)].compactMap { $0 }
        for url in targets {
            try? data.write(to: url, options: .atomic)
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
