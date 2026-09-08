import XCTest
@testable import Rolecall

/// P0-15: the background-refresh task must not spin up StoreKit or sleep. It reads a
/// plain Bool that `Store.refreshEntitlements()` caches in the App Group.
@MainActor
final class DigestBackgroundTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "DigestBGTests-\(UUID().uuidString)")
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        SharedContainer.lastKnownIsPlus = false
        super.tearDown()
    }

    func testHasWorkToDoGate() {
        let settings = AppSettings(defaults: defaults)
        let searches = SavedSearches(defaults: defaults)

        // Nothing on, not Plus -> nothing to do.
        XCTAssertFalse(Digest.hasWorkToDo(settings: settings, searches: searches, isPlus: false))

        // A digest toggle alone is enough.
        settings.morningRead = true
        XCTAssertTrue(Digest.hasWorkToDo(settings: settings, searches: searches, isPlus: false))
        settings.morningRead = false

        // A notifying saved search only counts when Plus is active.
        var s = SavedSearch(name: "Design in NYC", filter: RoleFilter())
        s.notify = true
        searches.add(s)
        XCTAssertFalse(Digest.hasWorkToDo(settings: settings, searches: searches, isPlus: false),
                       "saved-search alerts require Plus")
        XCTAssertTrue(Digest.hasWorkToDo(settings: settings, searches: searches, isPlus: true))
    }

    func testStoreCachesEntitlementBoolForTheBackgroundTask() async {
        SharedContainer.lastKnownIsPlus = true   // pretend a previous run set it
        let store = Store()
        await store.refreshEntitlements()
        // The test host has no entitlements, so isPlus is false — and refreshEntitlements
        // must have written that through to the App Group Bool the BG task reads.
        XCTAssertEqual(store.isPlus, false)
        XCTAssertEqual(SharedContainer.lastKnownIsPlus, false,
                       "refreshEntitlements must cache isPlus for the background task")
    }

    func testSharedContainerBoolRoundTrips() {
        SharedContainer.lastKnownIsPlus = true
        XCTAssertTrue(SharedContainer.lastKnownIsPlus)
        SharedContainer.lastKnownIsPlus = false
        XCTAssertFalse(SharedContainer.lastKnownIsPlus)
    }

    /// The alert path: a Plus subscriber with a notifying saved search that has a
    /// genuinely new matching role still produces work for the BG task, driven purely by
    /// the cached Bool (no StoreKit).
    func testAlertPathStillFiresFromCachedBool() {
        SharedContainer.lastKnownIsPlus = true
        let settings = AppSettings(defaults: defaults)      // all digests off by default
        let searches = SavedSearches(defaults: defaults)
        searches.add(SavedSearch(name: "PD", filter: RoleFilter(), notify: true))

        XCTAssertTrue(Digest.hasWorkToDo(settings: settings, searches: searches,
                                         isPlus: SharedContainer.lastKnownIsPlus),
                      "cached isPlus=true + a notifying saved search => BG task runs")

        SharedContainer.lastKnownIsPlus = false
        XCTAssertFalse(Digest.hasWorkToDo(settings: settings, searches: searches,
                                          isPlus: SharedContainer.lastKnownIsPlus))
    }
}
