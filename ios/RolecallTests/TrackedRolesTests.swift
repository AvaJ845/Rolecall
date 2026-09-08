import XCTest
@testable import Rolecall

@MainActor
final class TrackedRolesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: TrackedRoles!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TrackedRolesTests-\(UUID().uuidString)")
        store = TrackedRoles(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    private func role(_ url: String, firstSeen: Date = Date()) -> Role {
        Role(company: "Acme", title: "Product Designer", family: .design, location: nil,
             remote: nil, url: URL(string: url)!, firstSeen: firstSeen, lastVerified: nil)
    }

    func testSaveToggleAndCount() {
        let r = role("https://x/1")
        XCTAssertNil(store.status(for: r))
        store.toggleSaved(r)
        XCTAssertEqual(store.status(for: r), .saved)
        XCTAssertEqual(store.savedCount, 1)
        store.toggleSaved(r)
        XCTAssertNil(store.status(for: r), "toggles off")
        XCTAssertEqual(store.savedCount, 0)
    }

    func testApplyAndAdvanceStage() {
        let r = role("https://x/2")
        store.markApplied(r)
        XCTAssertTrue(store.status(for: r)?.isApplied == true)
        XCTAssertEqual(store.application(for: r)?.stage, .applied)

        store.updateApplication(for: r) { $0.stage = .recruiterScreen }
        XCTAssertEqual(store.application(for: r)?.stage, .recruiterScreen)
        XCTAssertGreaterThanOrEqual(store.application(for: r)!.updatedOn,
                                    store.application(for: r)!.appliedOn)

        store.unmarkApplied(r)
        XCTAssertNil(store.status(for: r))
    }

    func testMarkAppliedIsIdempotentAndPreservesDate() {
        let r = role("https://x/3")
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.markApplied(r, on: t0)
        store.updateApplication(for: r) { $0.stage = .offer }
        store.markApplied(r)  // must not reset
        XCTAssertEqual(store.application(for: r)?.appliedOn, t0)
        XCTAssertEqual(store.application(for: r)?.stage, .offer)
    }

    func testPersistenceAcrossInstances() {
        let r = role("https://x/4")
        store.toggleSaved(r)
        store.markApplied(role("https://x/5"))

        let reloaded = TrackedRoles(defaults: defaults)
        XCTAssertEqual(reloaded.status(for: r), .saved)
        XCTAssertEqual(reloaded.appliedCount, 1)
    }

    func testIsNewUsesLastVisit() {
        let old = role("https://x/6", firstSeen: Date(timeIntervalSinceNow: -10_000))
        let fresh = role("https://x/7", firstSeen: Date())
        XCTAssertFalse(store.isNew(fresh), "nothing is new on a first-ever launch")
        store.recordVisit(Date(timeIntervalSinceNow: -3_600))
        XCTAssertTrue(store.isNew(fresh))
        XCTAssertFalse(store.isNew(old))
    }

    func testPruneDropsSavedForDepartedRolesButKeepsApplications() {
        let stillLive = role("https://x/live")
        let goneSaved = role("https://x/gone-saved")
        let goneApplied = role("https://x/gone-applied")
        store.toggleSaved(stillLive)
        store.toggleSaved(goneSaved)
        store.markApplied(goneApplied)

        let board = Board(generatedUTC: Date(), count: 1, roles: [stillLive])
        store.prune(against: board)

        XCTAssertEqual(store.status(for: stillLive), .saved)
        XCTAssertNil(store.status(for: goneSaved), "saved role that left the board is dropped")
        XCTAssertTrue(store.status(for: goneApplied)?.isApplied == true, "application is kept")
    }

    func testWipeAll() {
        store.toggleSaved(role("https://x/8"))
        store.markApplied(role("https://x/9"))
        store.recordVisit()
        store.wipeAll()
        XCTAssertEqual(store.savedCount, 0)
        XCTAssertEqual(store.appliedCount, 0)
        XCTAssertEqual(store.lastVisit, .distantPast)
        XCTAssertTrue(TrackedRoles(defaults: defaults).states.isEmpty)
    }

    func testNotInterestedHides() {
        let r = role("https://x/10")
        store.setNotInterested(r)
        XCTAssertEqual(store.status(for: r)?.isHidden, true)
    }

    func testAutoClearDropsOnlyStaleApplications() {
        let fresh = role("https://x/fresh")
        let stale = role("https://x/stale")
        let saved = role("https://x/saved")
        store.markApplied(fresh, on: Date())
        // markApplied sets updatedOn == appliedOn, so this application is stale as-is.
        store.markApplied(stale, on: Date(timeIntervalSinceNow: -200 * 86400))
        store.toggleSaved(saved)

        store.autoClear(olderThanDays: 90)

        XCTAssertTrue(store.status(for: fresh)?.isApplied == true)
        XCTAssertNil(store.status(for: stale), "stale application cleared")
        XCTAssertEqual(store.status(for: saved), .saved, "saved roles untouched")
    }

    func testAppSettingsPersistAndReset() {
        let s = AppSettings(defaults: defaults)
        s.appearance = .dark
        s.morningRead = true
        s.alternateIconName = "AppIcon-Midnight"

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertTrue(reloaded.morningRead)
        XCTAssertEqual(reloaded.alternateIconName, "AppIcon-Midnight")

        reloaded.resetAll()
        XCTAssertEqual(reloaded.appearance, .system)
        XCTAssertNil(reloaded.alternateIconName)
        XCTAssertFalse(AppSettings(defaults: defaults).morningRead)
    }
}
