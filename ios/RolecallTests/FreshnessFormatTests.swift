import XCTest
@testable import Rolecall

final class FreshnessFormatTests: XCTestCase {

    func testCompactAgoKnownIntervals() {
        XCTAssertEqual(Freshness.compactAgo(0), "just now")
        XCTAssertEqual(Freshness.compactAgo(20), "just now")
        XCTAssertEqual(Freshness.compactAgo(12 * 60), "12m ago")
        XCTAssertEqual(Freshness.compactAgo(59 * 60), "59m ago")
        XCTAssertEqual(Freshness.compactAgo(60 * 60), "1h ago")
        XCTAssertEqual(Freshness.compactAgo(3 * 3600), "3h ago")
        XCTAssertEqual(Freshness.compactAgo(23 * 3600), "23h ago")
        XCTAssertEqual(Freshness.compactAgo(24 * 3600), "1d ago")
        XCTAssertEqual(Freshness.compactAgo(2 * 86400), "2d ago")
        XCTAssertEqual(Freshness.compactAgo(6 * 86400), "6d ago")
        XCTAssertEqual(Freshness.compactAgo(14 * 86400), "2w ago")
        XCTAssertEqual(Freshness.compactAgo(60 * 86400), "2mo ago")
        XCTAssertEqual(Freshness.compactAgo(400 * 86400), "1y ago")
    }

    func testCompactAgoFromDate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twelveMinAgo = now.addingTimeInterval(-12 * 60)
        XCTAssertEqual(Freshness.compactAgo(since: twelveMinAgo, relativeTo: now), "12m ago")
    }

    func testFullLine() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let seen = now.addingTimeInterval(-90 * 60)
        XCTAssertEqual(Freshness.line(for: seen, verified: true, relativeTo: now),
                       "verified live · 1h ago")
        XCTAssertEqual(Freshness.line(for: seen, verified: false, relativeTo: now),
                       "listed · 1h ago")
    }

    func testNeverNegative() {
        // A clock skew that puts the timestamp slightly in the future must not print
        // something absurd.
        XCTAssertEqual(Freshness.compactAgo(-30), "just now")
    }

    func testSectioningBandsByFreshness() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!

        func role(_ id: String, ageDays: Double) -> Role {
            Role(company: "Acme", title: "Designer \(id)", family: .design,
                 location: "NYC", remote: false,
                 url: URL(string: "https://jobs.example.com/\(id)")!,
                 firstSeen: now.addingTimeInterval(-ageDays * 86400), lastVerified: nil)
        }

        let roles = [role("a", ageDays: 0.1), role("b", ageDays: 3), role("c", ageDays: 20)]
        let sections = RoleSectioning.sections(from: roles, filter: RoleFilter(),
                                               now: now, calendar: cal)

        XCTAssertEqual(sections.map(\.band), [.today, .week, .earlier])
        XCTAssertEqual(sections[0].roles.count, 1)
        XCTAssertEqual(sections[1].roles.count, 1)
        XCTAssertEqual(sections[2].roles.count, 1)
    }

    func testFilterMatching() {
        let remoteResearch = Role(company: "Acme", title: "Researcher", family: .research,
                                  location: nil, remote: true,
                                  url: URL(string: "https://jobs.example.com/r")!,
                                  firstSeen: Date(), lastVerified: nil)
        var filter = RoleFilter()
        XCTAssertTrue(filter.matches(remoteResearch))

        filter.families = [.design]
        XCTAssertFalse(filter.matches(remoteResearch))

        filter.families = [.research]
        XCTAssertTrue(filter.matches(remoteResearch))

        filter.remoteOnly = true
        XCTAssertTrue(filter.matches(remoteResearch))

        let onsite = Role(company: "Acme", title: "Researcher", family: .research,
                          location: "NYC", remote: false,
                          url: URL(string: "https://jobs.example.com/r2")!,
                          firstSeen: Date(), lastVerified: nil)
        XCTAssertFalse(filter.matches(onsite))
    }
}
