import XCTest
import CryptoKit
@testable import Rolecall

/// P0-1: the board decode / sanitise / merge / write must not run on the main actor.
@MainActor
final class BoardStoreTests: XCTestCase {

    /// Start every case from a clean App Group container so `init`'s cache-hydration
    /// Task can't race a leftover snapshot into `board` mid-test.
    override func setUp() {
        super.setUp()
        for url in [SharedContainer.boardFile, Optional(SharedContainer.localBoardFile)].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A synthetic board with `roleCount` distinct roles, spread across ~400 companies so
    /// the merge does real dictionary work.
    private func synthRole(_ i: Int, base: Date) -> Role {
        let company: String = "Company " + String(i % 400)
        let title: String = "Product Designer " + String(i)
        let family: RoleFamily = (i % 4 == 0) ? .pm : .design
        let url: URL = URL(string: "https://boards.greenhouse.io/co/jobs/" + String(i))!
        let firstSeen: Date = base.addingTimeInterval(-Double(i))
        return Role(company: company, title: title, family: family, location: "New York, NY",
                    remote: (i % 2 == 0), url: url, firstSeen: firstSeen, lastVerified: nil)
    }

    private func synthBoard(roleCount: Int, generatedUTC: Date) -> Board {
        var roles: [Role] = []
        roles.reserveCapacity(roleCount)
        for i in 0..<roleCount { roles.append(synthRole(i, base: generatedUTC)) }
        return Board(generatedUTC: generatedUTC, count: roles.count, roles: roles)
    }

    /// `init` with a 5,000-role bundled board returns effectively instantly: no cache
    /// decode, no merge, no disk write on the main actor.
    func testInitIsFastWithAFiveThousandRoleBundledBoard() {
        let big = synthBoard(roleCount: 5000, generatedUTC: Date())

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = BoardStore(session: .shared,
                           remoteURL: BoardSource.remoteURL,
                           bundledBoard: big)
        }

        // The bundled path is one O(n) `sanitized()` filter and an assignment; the heavy
        // work is deferred to a Task on the cooperative pool. Generous ceiling for CI.
        XCTAssertLessThan(elapsed, .milliseconds(20),
                          "BoardStore.init must not decode/merge/write the cache on the main actor")
    }

    /// The off-main decode+sanitise+merge handles a multi-thousand-role remote board and
    /// reports the correct added count.
    func testDecodeAndMergeHandlesThousandsOfRoles() async throws {
        let current = synthBoard(roleCount: 3000, generatedUTC: Date(timeIntervalSinceNow: -3600))
        let remote = synthBoard(roleCount: 5000, generatedUTC: Date())   // superset, newer
        let data = try remote.encoded()

        let outcome = try await BoardStore.decodeAndMerge(remoteData: data, into: current)
        let merged = try XCTUnwrap(outcome)

        XCTAssertEqual(merged.board.roles.count, 5000, "newer snapshot defines membership")
        XCTAssertEqual(merged.added, 2000, "2,000 roles are new relative to the 3,000 already held")
        XCTAssertEqual(merged.board.generatedUTC.timeIntervalSince1970,
                       remote.generatedUTC.timeIntervalSince1970, accuracy: 0.001,
                       "generated time comes from the newer snapshot (JSON epoch round-trip)")
    }

    /// A remote board that lost more than half its roles is rejected off-main, exactly as
    /// the on-main path did before.
    func testDecodeAndMergeRejectsImplausiblyThinBoard() async throws {
        let current = synthBoard(roleCount: 4000, generatedUTC: Date(timeIntervalSinceNow: -3600))
        let thin = synthBoard(roleCount: 1000, generatedUTC: Date())
        let outcome = try await BoardStore.decodeAndMerge(remoteData: try thin.encoded(), into: current)
        XCTAssertNil(outcome, "a board that shed >half its roles must not replace the trusted one")
    }

    // MARK: - P0-7: board + signature as one atomically-fetched artifact

    private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    private func mockSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private func envelope(sig: String, boardData: Data) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "format": 2, "sig": sig,
            "board": String(decoding: boardData, as: UTF8.self),
        ])
    }

    /// The v2 envelope: one request returns board + signature, verified, merged.
    func testRefreshUsesV2EnvelopeInOneRequest() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let key = Curve25519.Signing.PrivateKey()
        let remote = synthBoard(roleCount: 40, generatedUTC: Date())
        let boardData = try remote.encoded()
        let sig = hex(try key.signature(for: boardData))
        let env = envelope(sig: sig, boardData: boardData)

        MockURLProtocol.handler = { req in
            let path = req.url!.path
            let ok = { (d: Data) in
                (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                 headerFields: nil)!, d)
            }
            if path.hasSuffix("board.v2.json") { return ok(env) }
            return (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil,
                                    headerFields: nil)!, Data())
        }

        let store = BoardStore(session: mockSession(),
                               boardPublicKeyHex: hex(key.publicKey.rawRepresentation),
                               bundledBoard: .empty)
        await store.refresh(userInitiated: true)

        XCTAssertEqual(store.board.roles.count, 40)
        XCTAssertEqual(store.lastRefreshOutcome, .updated(added: 40))
        XCTAssertEqual(MockURLProtocol.requestCount, 1, "the envelope is a single GET")
    }

    /// v2 missing (older edge) → fall back to the legacy two files.
    func testRefreshFallsBackToLegacyTwoFilesWhenV2Missing() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let key = Curve25519.Signing.PrivateKey()
        let remote = synthBoard(roleCount: 30, generatedUTC: Date())
        let boardData = try remote.encoded()
        let sig = hex(try key.signature(for: boardData))

        MockURLProtocol.handler = { req in
            let path = req.url!.path
            func resp(_ code: Int, _ d: Data) -> (HTTPURLResponse, Data) {
                (HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: "HTTP/1.1",
                                 headerFields: nil)!, d)
            }
            if path.hasSuffix("board.v2.json") { return resp(404, Data()) }
            if path.hasSuffix("board.json.sig") { return resp(200, Data(sig.utf8)) }
            if path.hasSuffix("board.json") { return resp(200, boardData) }
            return resp(404, Data())
        }

        let store = BoardStore(session: mockSession(),
                               boardPublicKeyHex: hex(key.publicKey.rawRepresentation),
                               bundledBoard: .empty)
        await store.refresh(userInitiated: true)

        XCTAssertEqual(store.board.roles.count, 30)
        XCTAssertEqual(store.lastRefreshOutcome, .updated(added: 30))
    }

    /// The deploy-window skew: legacy board is fresh but the cached .sig is for the OLD
    /// board. The app must retry the pair once (cache-busting) and then succeed — never a
    /// silent no-op.
    func testLegacySignatureSkewTriggersExactlyOneCacheBustingRetry() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let key = Curve25519.Signing.PrivateKey()
        let newBoard = try synthBoard(roleCount: 25, generatedUTC: Date()).encoded()
        let newSig = hex(try key.signature(for: newBoard))
        let staleSig = hex(try key.signature(for: Data("an older board".utf8)))

        MockURLProtocol.handler = { req in
            let path = req.url!.path
            let busted = (req.url!.query ?? "").contains("_cb=")
            func resp(_ code: Int, _ d: Data) -> (HTTPURLResponse, Data) {
                (HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: "HTTP/1.1",
                                 headerFields: nil)!, d)
            }
            if path.hasSuffix("board.v2.json") { return resp(404, Data()) }
            if path.hasSuffix("board.json.sig") {
                return resp(200, Data((busted ? newSig : staleSig).utf8))   // stale until cache-busted
            }
            if path.hasSuffix("board.json") { return resp(200, newBoard) }
            return resp(404, Data())
        }

        let store = BoardStore(session: mockSession(),
                               boardPublicKeyHex: hex(key.publicKey.rawRepresentation),
                               bundledBoard: .empty)
        await store.refresh(userInitiated: true)

        XCTAssertEqual(store.board.roles.count, 25, "retry with cache-buster resolved the skew")
        XCTAssertEqual(store.lastRefreshOutcome, .updated(added: 25))
    }
}
