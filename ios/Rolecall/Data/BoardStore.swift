import Foundation
import SwiftUI

/// Owns the board the whole app renders.
///
/// Launch path: the bundled snapshot is assigned synchronously in `init`, so the list has
/// content on the first frame — no spinner, no empty flash — and `init` does **no** JSON
/// decode, sanitise pass over the cache, merge, or disk write on the main actor. The
/// cache read + merge happens a beat later off the main actor and swaps in. Then
/// `refresh()` tries the one remote URL; its decode/sanitise/merge also runs off the main
/// actor. Everything is on device; there is no account and no server round-trip beyond
/// fetching the public board file.
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

    init(session: URLSession = .shared,
         remoteURL: URL = BoardSource.remoteURL,
         bundledBoard: Board = BoardSource.bundledBoard()) {
        self.session = session
        self.remoteURL = remoteURL

        // Frame 1: the bundled snapshot and nothing else. `sanitized()` is a single O(n)
        // filter over our own trusted engine output — cheap enough for the first frame;
        // the cache decode + merge + disk write, which are not, move off the main actor.
        let bundled = bundledBoard.sanitized()
        self.board = bundled

        // A beat later: read the previously-merged cache, merge it over the bundled
        // board, publish, and persist — all off the main actor.
        Task { await self.hydrateFromCache(bundled: bundled) }
    }

    /// Merge the on-disk cache over the bundled board and publish it, then write the
    /// result back once. All of the heavy lifting runs on the cooperative pool.
    private func hydrateFromCache(bundled: Board) async {
        if let hydrated = await Self.mergedCache(over: bundled) {
            self.board = hydrated
            await Self.persist(hydrated)
        } else {
            // Nothing newer cached; still make sure the container has a copy for the widget.
            await Self.persist(bundled)
        }
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
            // The downloaded board must carry a valid Ed25519 signature from our own key.
            // A bad or missing signature -> ignore it entirely, keep the trusted board.
            guard let signatureHex = try? await fetchSignature(),
                  BoardSignature.isValid(board: data, signatureHex: signatureHex) else {
                lastRefreshOutcome = userInitiated ? .unreachable : .upToDate
                return
            }
            // Decode + sanitise + plausibility check + merge + the added-count diff, all
            // off the main actor. Only the assignment and the disk write come back here.
            let current = board
            guard let outcome = try await Self.decodeAndMerge(remoteData: data, into: current) else {
                lastRefreshOutcome = .upToDate
                return
            }
            board = outcome.board
            await Self.persist(outcome.board)
            lastRefreshOutcome = .updated(added: outcome.added)
        } catch {
            lastRefreshOutcome = userInitiated ? .unreachable : .upToDate
        }
    }

    private func fetchSignature() async throws -> String {
        var request = URLRequest(url: BoardSignature.signatureURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 4096
        else { throw URLError(.badServerResponse) }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Off-main-actor work
    //
    // These are `nonisolated` `async` statics: per SE-0338 they run on the generic
    // cooperative executor, never the caller's (main) actor. They take and return `Board`
    // value types, so nothing shared is touched.

    /// The cached snapshot merged over `bundled`, or `nil` when the cache is absent or
    /// not strictly newer than what shipped in this build.
    nonisolated static func mergedCache(over bundled: Board) async -> Board? {
        guard let cached = SharedContainer.currentBoard()?.sanitized(),
              cached.generatedUTC > bundled.generatedUTC
        else { return nil }
        return cached.merging(bundled)
    }

    /// Decode the downloaded bytes, sanitise, gate on `isPlausibleReplacement`, then merge
    /// over `current` and count what is new. `nil` means the candidate did not clear the
    /// plausibility bar and must be ignored.
    nonisolated static func decodeAndMerge(remoteData: Data,
                                           into current: Board) async throws -> (board: Board, added: Int)? {
        let remote = try Board.decode(from: remoteData).sanitized()
        guard remote.isPlausibleReplacement(for: current) else { return nil }
        let before = Set(current.roles.map(\.id))
        let merged = current.merging(remote)
        let added = merged.roles.filter { !before.contains($0.id) }.count
        return (merged, added)
    }

    /// Write the board to the shared container. Off the main actor; runs at most once per
    /// refresh.
    nonisolated static func persist(_ board: Board) async {
        SharedContainer.writeBoard(board)
    }
}
