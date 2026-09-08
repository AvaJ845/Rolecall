import Foundation
import SwiftUI

/// Owns the board the whole app renders.
///
/// Launch path: the bundled snapshot is loaded synchronously in `init`, so the list has
/// content on the first frame — no spinner, no empty flash. Then `refresh()` tries the
/// one remote URL and merges anything newer. Everything is on device; there is no
/// account and no server round-trip beyond fetching the public board file.
@MainActor
final class BoardStore: ObservableObject {

    @Published private(set) var board: Board
    @Published private(set) var lastRefreshOutcome: RefreshOutcome = .idle

    enum RefreshOutcome: Equatable {
        case idle
        case refreshing
        case updated(added: Int)
        case upToDate
        case unreachable
    }

    private let session: URLSession
    private let remoteURL: URL

    /// Hard ceiling on a downloaded board (thousands of roles are well under 2 MB). A
    /// response larger than this is treated as hostile and ignored.
    private let maxBoardBytes = 8 * 1024 * 1024

    init(session: URLSession = .shared, remoteURL: URL = BoardSource.remoteURL) {
        self.session = session
        self.remoteURL = remoteURL

        // Prefer a previously merged snapshot the app wrote to the shared container, if it
        // is newer than what shipped in this build; otherwise the bundled file. Both are
        // sanitised (https-only, de-duped) before anything renders them.
        let bundled = BoardSource.bundledBoard().sanitized()
        if let cached = SharedContainer.currentBoard()?.sanitized(),
           cached.generatedUTC > bundled.generatedUTC {
            self.board = cached.merging(bundled)
        } else {
            self.board = bundled
        }
        SharedContainer.writeBoard(board)
    }

    /// Try the single remote URL and merge a newer snapshot. Never throws to the caller;
    /// a 404 (the placeholder host) or an offline device just leaves the board as-is.
    ///
    /// `userInitiated` is false for the silent refresh on launch — a failure then is not
    /// worth a banner, because the reader never asked. A pull-to-refresh that fails does
    /// deserve the quiet "showing saved roles" line.
    func refresh(userInitiated: Bool = false) async {
        lastRefreshOutcome = .refreshing
        do {
            var request = URLRequest(url: remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastRefreshOutcome = .upToDate   // nothing published yet; not an error worth showing
                return
            }
            guard data.count <= maxBoardBytes else {
                lastRefreshOutcome = .upToDate
                return
            }
            let remote = try Board.decode(from: data).sanitized()
            guard remote.isPlausibleReplacement(for: board) else {
                lastRefreshOutcome = .upToDate
                return
            }
            let before = Set(board.roles.map(\.id))
            let merged = board.merging(remote)
            let added = merged.roles.filter { !before.contains($0.id) }.count
            board = merged
            SharedContainer.writeBoard(merged)
            lastRefreshOutcome = .updated(added: added)
        } catch {
            lastRefreshOutcome = userInitiated ? .unreachable : .upToDate
        }
    }
}
