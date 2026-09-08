import XCTest
@testable import Rolecall

@MainActor
final class SavedSearchTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: SavedSearches!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SavedSearchTests-\(UUID().uuidString)")
        store = SavedSearches(defaults: defaults)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    private func role(_ url: String, company: String = "Acme", title: String = "Product Designer",
                      family: RoleFamily = .design, location: String? = nil,
                      firstSeen: Date = Date()) -> Role {
        Role(company: company, title: title, family: family, location: location, remote: nil,
             url: URL(string: url)!, firstSeen: firstSeen, lastVerified: nil)
    }

    func testFreeLimitAndPersistence() {
        XCTAssertTrue(store.canAddWithoutPlus)
        store.add(SavedSearch(name: "One", filter: RoleFilter()))
        XCTAssertFalse(store.canAddWithoutPlus, "free tier keeps exactly one")
        store.add(SavedSearch(name: "Two", filter: RoleFilter()))   // gate is enforced by the UI, store still stores

        let reloaded = SavedSearches(defaults: defaults)
        XCTAssertEqual(reloaded.searches.map(\.name), ["One", "Two"])
    }

    func testMatchesFilterAndQuery() {
        var f = RoleFilter(); f.families = [.design]
        let s = SavedSearch(name: "s", filter: f, query: "figma")
        XCTAssertTrue(s.matches(role("https://x/1", company: "Figma", title: "Brand Designer")))
        XCTAssertFalse(s.matches(role("https://x/2", company: "Ramp", title: "Product Designer")), "query miss")
        XCTAssertFalse(s.matches(role("https://x/3", company: "Figma", title: "PM", family: .pm)), "family miss")
    }

    func testNewRolesWindowing() {
        let created = Date(timeIntervalSinceNow: -3600)
        var s = SavedSearch(name: "s", filter: RoleFilter())
        // fake the createdAt via round-trip is awkward; use lastNotifiedAt instead
        s.lastNotifiedAt = created
        let old = role("https://x/old", firstSeen: created.addingTimeInterval(-100))
        let fresh = role("https://x/new", firstSeen: created.addingTimeInterval(600))
        let board = Board(generatedUTC: Date(), count: 2, roles: [old, fresh])
        XCTAssertEqual(s.newRoles(in: board).map(\.id), ["https://x/new"])
    }

    func testMarkNotifiedAdvancesWindow() {
        store.add(SavedSearch(name: "s", filter: RoleFilter()))
        let id = store.searches[0].id
        let t = Date()
        store.markNotified(id, at: t)
        XCTAssertEqual(store.searches[0].lastNotifiedAt?.timeIntervalSince1970 ?? 0,
                       t.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWipe() {
        store.add(SavedSearch(name: "s", filter: RoleFilter()))
        store.wipeAll()
        XCTAssertTrue(store.searches.isEmpty)
        XCTAssertTrue(SavedSearches(defaults: defaults).searches.isEmpty)
    }

    // MARK: advanced RoleFilter

    func testSeniorityParsing() {
        func sen(_ t: String) -> Seniority { role("https://x/1", title: t).seniority }
        XCTAssertEqual(sen("Staff Product Designer"), .staff)
        XCTAssertEqual(sen("Senior Product Designer"), .senior)
        XCTAssertEqual(sen("Lead Product Designer"), .lead)
        XCTAssertEqual(sen("Principal Designer"), .principal)
        XCTAssertEqual(sen("Director of Design"), .director)
        XCTAssertEqual(sen("Head of Design"), .director)
        XCTAssertEqual(sen("Design Intern"), .intern)
        XCTAssertEqual(sen("Junior UX Designer"), .junior)
        XCTAssertEqual(sen("Product Designer"), .mid)
    }

    func testAdvancedFilterMatching() {
        var f = RoleFilter()
        f.seniorities = [.staff]
        XCTAssertTrue(f.matches(role("https://x/1", title: "Staff Product Designer")))
        XCTAssertFalse(f.matches(role("https://x/2", title: "Senior Product Designer")))

        f = RoleFilter()
        let now = Date()
        f.postedWithinDays = 3
        XCTAssertTrue(f.matches(role("https://x/3", firstSeen: now.addingTimeInterval(-2 * 86_400)), now: now))
        XCTAssertFalse(f.matches(role("https://x/4", firstSeen: now.addingTimeInterval(-5 * 86_400)), now: now))

        f = RoleFilter()
        f.excludedCompanies = ["Figma"]
        XCTAssertFalse(f.matches(role("https://x/5", company: "figma")), "case-insensitive exclude")
        XCTAssertTrue(f.matches(role("https://x/6", company: "Ramp")))
    }

    func testFilterDecodesFromLegacyJSONWithoutAdvancedKeys() throws {
        let legacy = #"{"families":["design"],"remoteOnly":false,"usAndRemoteOnly":true}"#
        let f = try JSONDecoder().decode(RoleFilter.self, from: Data(legacy.utf8))
        XCTAssertEqual(f.families, [.design])
        XCTAssertTrue(f.seniorities.isEmpty)
        XCTAssertNil(f.postedWithinDays)
        XCTAssertFalse(f.usesPlusFilters)
    }
}
