import XCTest
@testable import Rolecall

final class BoardDecodingTests: XCTestCase {

    /// The engine's real `data/board.json`, bundled into this test target.
    private func realBoardData() throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "board", withExtension: "json"),
                                "board.json must be bundled in the test target")
        return try Data(contentsOf: url)
    }

    func testDecodesRealBoardWithZeroDataLoss() throws {
        let data = try realBoardData()
        let board = try Board.decode(from: data)

        // Every role in the file survives decoding — no silently dropped rows.
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rawRoles = raw?["roles"] as? [[String: Any]]
        let rawCount = rawRoles?.count ?? -1

        XCTAssertEqual(board.roles.count, rawCount, "decoded role count must match the file")
        XCTAssertEqual(board.count, board.roles.count, "declared count must match actual roles")
        XCTAssertGreaterThan(board.roles.count, 0)
    }

    func testEveryFieldRoundTrips() throws {
        let data = try realBoardData()
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawRoles = try XCTUnwrap(raw["roles"] as? [[String: Any]])
        let board = try Board.decode(from: data)

        for (rawRole, role) in zip(rawRoles, board.roles) {
            XCTAssertEqual(role.company, rawRole["company"] as? String)
            XCTAssertEqual(role.title, rawRole["title"] as? String)
            XCTAssertEqual(role.family.rawValue, rawRole["family"] as? String)
            XCTAssertEqual(role.url.absoluteString, rawRole["url"] as? String)
            if let firstSeen = rawRole["first_seen"] as? Double {
                XCTAssertEqual(role.firstSeen.timeIntervalSince1970, firstSeen, accuracy: 0.001)
            }
            if rawRole["last_verified"] is NSNull || rawRole["last_verified"] == nil {
                XCTAssertNil(role.lastVerified)
            }
        }
    }

    // `meta` is optional. A board from before the engine stamped it must still
    // decode (meta == nil); a board with it exposes the ruleset.
    func testDecodesBoardWithoutMeta() throws {
        let json = Data("""
        {"generated_utc": 1788800000, "count": 1, "roles": [
          {"company":"Acme","title":"Product Designer","family":"design",
           "location":"NYC","remote":false,"url":"https://jobs.example.com/1",
           "first_seen":1788000000,"last_verified":null}
        ]}
        """.utf8)
        let board = try Board.decode(from: json)
        XCTAssertNil(board.meta)
        XCTAssertEqual(board.roles.count, 1)
    }

    func testDecodesBoardWithMeta() throws {
        let json = Data("""
        {"generated_utc": 1788800000, "count": 1,
         "meta": {"classifier_version":"2026-09-08","include_pm":true,"vertical":"product-design"},
         "roles": [
          {"company":"Acme","title":"Product Designer","family":"design",
           "location":"NYC","remote":false,"url":"https://jobs.example.com/1",
           "first_seen":1788000000,"last_verified":null}
        ]}
        """.utf8)
        let board = try Board.decode(from: json)
        XCTAssertEqual(board.meta?.classifierVersion, "2026-09-08")
        XCTAssertEqual(board.meta?.includePM, true)
        XCTAssertEqual(board.meta?.vertical, "product-design")
        XCTAssertEqual(board.sanitized().meta?.classifierVersion, "2026-09-08")
        let reencoded = try board.encoded()
        XCTAssertEqual(try Board.decode(from: reencoded).meta, board.meta)
    }

    func testFamilyCoverage() throws {
        let board = try Board.decode(from: try realBoardData())
        let families = Set(board.roles.map(\.family))
        // The engine classifies into these four; all should appear in a full board.
        XCTAssertTrue(families.isSubset(of: Set(RoleFamily.allCases)))
    }

    func testMergePrefersNewerSnapshotMembership() throws {
        let now = Date()
        let old = Role(company: "Acme", title: "Product Designer", family: .design,
                       location: "NYC", remote: false,
                       url: URL(string: "https://jobs.example.com/1")!,
                       firstSeen: now.addingTimeInterval(-86400), lastVerified: nil)
        let stale = Role(company: "Acme", title: "Old Role", family: .design,
                         location: nil, remote: nil,
                         url: URL(string: "https://jobs.example.com/stale")!,
                         firstSeen: now.addingTimeInterval(-200000), lastVerified: nil)
        let boardOld = Board(generatedUTC: now.addingTimeInterval(-3600), count: 2,
                             roles: [old, stale])

        let verified = Role(company: "Acme", title: "Product Designer", family: .design,
                            location: "NYC", remote: false,
                            url: URL(string: "https://jobs.example.com/1")!,
                            firstSeen: now, lastVerified: now)
        let boardNew = Board(generatedUTC: now, count: 1, roles: [verified])

        let merged = boardOld.merging(boardNew)
        XCTAssertEqual(merged.roles.count, 1, "role dropped by the newer engine run disappears")
        XCTAssertEqual(merged.roles.first?.id, "https://jobs.example.com/1")
        XCTAssertEqual(merged.roles.first?.lastVerified, now, "keeps the newer verify time")
        XCTAssertEqual(merged.roles.first?.firstSeen, now.addingTimeInterval(-86400),
                       "keeps the earliest first-seen")
    }
}
