import XCTest
@testable import Rolecall

/// P0-1: the board decode / sanitise / merge / write must not run on the main actor.
@MainActor
final class BoardStoreTests: XCTestCase {

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
}
