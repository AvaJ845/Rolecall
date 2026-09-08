import XCTest
@testable import Rolecall

/// Pure list/board logic: sanitisation, replacement gating, filtering, search, sectioning.
final class ListLogicTests: XCTestCase {

    private func role(_ url: String,
                      company: String = "Acme",
                      title: String = "Product Designer",
                      family: RoleFamily = .design,
                      location: String? = nil,
                      remote: Bool? = nil,
                      firstSeen: Date = Date(),
                      lastVerified: Date? = nil) -> Role {
        Role(company: company, title: title, family: family, location: location,
             remote: remote, url: URL(string: url)!,
             firstSeen: firstSeen, lastVerified: lastVerified)
    }

    // MARK: US / region filter

    func testLooksNonUS() {
        XCTAssertFalse(role("https://x/1", location: nil).looksNonUS, "unknown location passes")
        XCTAssertFalse(role("https://x/2", location: "New York, NY").looksNonUS)
        XCTAssertFalse(role("https://x/3", location: "United States").looksNonUS)
        XCTAssertFalse(role("https://x/4", location: "Remote within Canada or United States").looksNonUS,
                       "a US option present -> passes")
        XCTAssertFalse(role("https://x/5", location: "London", remote: true).looksNonUS,
                       "remote overrides location")
        XCTAssertTrue(role("https://x/6", location: "London, United Kingdom").looksNonUS)
        XCTAssertTrue(role("https://x/7", location: "Singapore").looksNonUS)
        XCTAssertTrue(role("https://x/8", location: "Tel Aviv, Israel").looksNonUS)
    }

    func testDefaultFilterHidesNonUS() {
        let f = RoleFilter()
        XCTAssertTrue(f.matches(role("https://x/1", location: "Austin, TX")))
        XCTAssertFalse(f.matches(role("https://x/2", location: "Berlin, Germany")))
        var wide = f
        wide.usAndRemoteOnly = false
        XCTAssertTrue(wide.matches(role("https://x/3", location: "Berlin, Germany")))
        XCTAssertTrue(wide.isActive, "worldwide is a non-default choice")
    }

    // MARK: sanitize

    func testSanitizeDropsNonHTTPSAndDuplicates() {
        let board = Board(generatedUTC: Date(), count: 4, roles: [
            role("https://jobs.example.com/1"),
            role("http://jobs.example.com/2"),                 // insecure -> dropped
            role("https://jobs.example.com/1"),                // dup -> dropped
            role("https://jobs.example.com/3"),
        ])
        let clean = board.sanitized()
        XCTAssertEqual(clean.roles.map(\.id),
                       ["https://jobs.example.com/1", "https://jobs.example.com/3"])
        XCTAssertEqual(clean.count, clean.roles.count)
    }

    // MARK: replacement gating

    func testPlausibleReplacementRules() {
        let now = Date()
        let current = Board(generatedUTC: now, count: 10,
                            roles: (0..<10).map { role("https://x/\($0)") })

        let newerFull = Board(generatedUTC: now.addingTimeInterval(60), count: 10,
                              roles: (0..<10).map { role("https://y/\($0)") })
        XCTAssertTrue(newerFull.isPlausibleReplacement(for: current))

        let older = Board(generatedUTC: now.addingTimeInterval(-60), count: 10,
                          roles: newerFull.roles)
        XCTAssertFalse(older.isPlausibleReplacement(for: current), "not strictly newer")

        let empty = Board(generatedUTC: now.addingTimeInterval(60), count: 0, roles: [])
        XCTAssertFalse(empty.isPlausibleReplacement(for: current), "empty snapshot rejected")

        let gutted = Board(generatedUTC: now.addingTimeInterval(60), count: 3,
                           roles: Array(newerFull.roles.prefix(3)))
        XCTAssertFalse(gutted.isPlausibleReplacement(for: current), "lost >half its roles")
    }

    // MARK: filter

    func testDefaultFilterIsDesignVerticalAndExcludesPM() {
        let f = RoleFilter()
        XCTAssertFalse(f.isActive, "the default design view is not 'active'")
        XCTAssertTrue(f.matches(role("https://x/1", family: .design)))
        XCTAssertTrue(f.matches(role("https://x/2", family: .designEng)))
        XCTAssertTrue(f.matches(role("https://x/3", family: .research)))
        XCTAssertFalse(f.matches(role("https://x/4", family: .pm)), "PM is off by default")
    }

    func testFilterMatchesFamilyAndRemote() {
        var f = RoleFilter()
        f.families = [.design, .research]
        XCTAssertTrue(f.matches(role("https://x/1", family: .design)))
        XCTAssertFalse(f.matches(role("https://x/2", family: .pm)))
        XCTAssertTrue(f.isActive, "narrowing off the default counts as active")

        f = RoleFilter(); f.families = [.pm]
        XCTAssertTrue(f.matches(role("https://x/1", family: .pm)), "PM shows when explicitly chosen")

        f = RoleFilter(); f.remoteOnly = true
        XCTAssertTrue(f.matches(role("https://x/3", family: .design, remote: true)))
        XCTAssertFalse(f.matches(role("https://x/4", family: .design, remote: nil)),
                       "unknown remote is not remote")
        XCTAssertFalse(f.matches(role("https://x/5", family: .design, remote: false)))
    }

    // MARK: search

    func testSearchIsCaseInsensitiveOnCompanyOrTitle() {
        let roles = [
            role("https://x/1", company: "Figma", title: "Brand Designer"),
            role("https://x/2", company: "Ramp", title: "Staff Product Designer"),
            role("https://x/3", company: "Linear", title: "Design Engineer"),
        ]
        XCTAssertEqual(RoleListView.search(roles, query: "figma").map(\.id), ["https://x/1"])
        XCTAssertEqual(RoleListView.search(roles, query: "  STAFF ").map(\.id), ["https://x/2"])
        XCTAssertEqual(Set(RoleListView.search(roles, query: "design").map(\.id)).count, 3)
        XCTAssertEqual(RoleListView.search(roles, query: "").count, 3, "blank query is a no-op")
    }

    // MARK: sectioning

    func testSectioningBucketsByFreshnessDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!

        let roles = [
            role("https://x/today", firstSeen: now.addingTimeInterval(-3600)),
            role("https://x/week", firstSeen: now.addingTimeInterval(-3 * 86400)),
            role("https://x/old", firstSeen: now.addingTimeInterval(-40 * 86400)),
        ]
        let sections = RoleSectioning.sections(from: roles, filter: RoleFilter(),
                                               now: now, calendar: cal)
        XCTAssertEqual(sections.map(\.band), [.today, .week, .earlier])
        XCTAssertEqual(sections.map { $0.roles.count }, [1, 1, 1])
    }

    func testSectioningSortsNewestFirstWithinABand() {
        let now = Date()
        let a = role("https://x/a", firstSeen: now.addingTimeInterval(-100))
        let b = role("https://x/b", firstSeen: now.addingTimeInterval(-50))
        let sections = RoleSectioning.sections(from: [a, b], filter: RoleFilter(), now: now)
        XCTAssertEqual(sections.first?.roles.map(\.id), ["https://x/b", "https://x/a"])
    }

    func testSectioningDropsEmptyBands() {
        let now = Date()
        let roles = [role("https://x/1", firstSeen: now.addingTimeInterval(-1000))]
        let sections = RoleSectioning.sections(from: roles, filter: RoleFilter(), now: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.band, .today)
    }
}
