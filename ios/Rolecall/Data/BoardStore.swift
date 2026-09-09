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
    private let remoteURLV2: URL
    /// The Ed25519 public key a downloaded board must be signed under. Defaults to the
    /// app's own committed key; injectable so tests can exercise the fetch/verify paths.
    private let boardPublicKeyHex: String

    /// Hard ceiling on a downloaded board (thousands of roles are well under 2 MB). A
    /// response larger than this is treated as hostile and ignored.
    private let maxBoardBytes = 8 * 1024 * 1024

    /// A board plus the signature that covers its exact bytes, fetched together.
    private struct SignedBoard {
        let board: Data
        let signatureHex: String
    }

    init(session: URLSession = .shared,
         remoteURL: URL = BoardSource.remoteURL,
         remoteURLV2: URL = BoardSource.remoteURLV2,
         boardPublicKeyHex: String = BoardSignature.publicKeyHex,
         bundledBoard: Board = BoardSource.bundledBoard()) {
        self.session = session
        self.remoteURL = remoteURL
        self.remoteURLV2 = remoteURLV2
        self.boardPublicKeyHex = boardPublicKeyHex

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
            // One consistent (board bytes, signature). Never a decode before the
            // signature check; the 8 MB cap and 15 s timeout still apply per request.
            guard let verified = try await fetchVerifiedBoard(userInitiated: userInitiated) else {
                return   // fetchVerifiedBoard already set lastRefreshOutcome
            }
            // Decode + sanitise + plausibility check + merge + the added-count diff, all
            // off the main actor. Only the assignment and the disk write come back here.
            let current = board
            guard let outcome = try await Self.decodeAndMerge(remoteData: verified, into: current) else {
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

    /// Board bytes whose Ed25519 signature is verified against our key, or `nil` (having
    /// set `lastRefreshOutcome`). Prefer the `board.v2.json` envelope — one request, so
    /// board + signature can never be out of sync. Fall back to the legacy two files for
    /// an edge that hasn't picked up v2 yet, and if their signature check fails, retry the
    /// pair once with a cache-buster to close the Cloudflare deploy-skew window.
    private func fetchVerifiedBoard(userInitiated: Bool) async throws -> Data? {
        func fail() -> Data? {
            lastRefreshOutcome = userInitiated ? .unreachable : .upToDate
            return nil
        }

        if let env = try await fetchEnvelope(cacheBust: false) {
            // The envelope is internally consistent; a bad signature here is a real
            // failure, not a cache skew, so there is nothing to retry.
            return BoardSignature.isValid(board: env.board, signatureHex: env.signatureHex,
                                          keyHex: boardPublicKeyHex)
                ? env.board : fail()
        }

        for cacheBust in [false, true] {
            if let pair = try await fetchLegacyPair(cacheBust: cacheBust),
               BoardSignature.isValid(board: pair.board, signatureHex: pair.signatureHex,
                                      keyHex: boardPublicKeyHex) {
                return pair.board
            }
        }
        return fail()
    }

    private func fetchEnvelope(cacheBust: Bool) async throws -> SignedBoard? {
        let (data, response) = try await get(cacheBust ? Self.cacheBusted(remoteURLV2) : remoteURLV2,
                                             timeout: 15)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= maxBoardBytes,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let boardText = obj["board"] as? String,
              let sigHex = obj["sig"] as? String
        else { return nil }
        // The envelope embeds board.json verbatim as a JSON string; its UTF-8 bytes are
        // byte-for-byte what the engine signed.
        let boardBytes = Data(boardText.utf8)
        guard boardBytes.count <= maxBoardBytes else { return nil }
        return SignedBoard(board: boardBytes, signatureHex: sigHex)
    }

    private func fetchLegacyPair(cacheBust: Bool) async throws -> SignedBoard? {
        let boardURL = cacheBust ? Self.cacheBusted(remoteURL) : remoteURL
        let sigURL = cacheBust ? Self.cacheBusted(BoardSignature.signatureURL) : BoardSignature.signatureURL

        let (data, response) = try await get(boardURL, timeout: 15)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= maxBoardBytes
        else { return nil }

        let (sigData, sigResponse) = try await get(sigURL, timeout: 10)
        guard let sigHTTP = sigResponse as? HTTPURLResponse, (200..<300).contains(sigHTTP.statusCode),
              sigData.count < 4096
        else { return nil }

        return SignedBoard(board: data, signatureHex: String(decoding: sigData, as: UTF8.self))
    }

    private func get(_ url: URL, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        return try await session.data(for: request)
    }

    /// Append a throwaway query item so a retry bypasses the edge/CDN cache, not just the
    /// on-device URL cache.
    private static func cacheBusted(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "_cb", value: String(Int(Date().timeIntervalSince1970))))
        comps.queryItems = items
        return comps.url ?? url
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
