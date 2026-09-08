import XCTest
@testable import Rolecall

/// P0-4: TTL cache + Wi-Fi-only short-circuit for the on-device liveness check.
@MainActor
final class FreshnessCacheTests: XCTestCase {

    private let jobURL = URL(string: "https://boards.greenhouse.io/acme/jobs/4567890")!

    /// A clock a test can advance by hand.
    private final class MutableClock: @unchecked Sendable {
        var now: Date
        init(_ start: Date = Date()) { self.now = start }
        var read: @Sendable () -> Date { { [self] in self.now } }
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func checker(cache: FreshnessCache = FreshnessCache(),
                         ttl: TimeInterval = FreshnessChecker.defaultTTL,
                         cellular: Bool = false) -> FreshnessChecker {
        .ephemeral(protocolClasses: [MockURLProtocol.self],
                   cache: cache, ttl: ttl, isCellular: { cellular })
    }

    // MARK: cache

    func testSecondOpenWithinTTLMakesNoRequest() async {
        MockURLProtocol.stub(statusCode: 200, body: "<h1>Product Designer</h1>")
        let sut = checker()

        let first = await sut.check(jobURL, wifiOnly: false)
        let second = await sut.check(jobURL, wifiOnly: false)

        XCTAssertEqual(first, .liveJustChecked)
        XCTAssertEqual(second, .liveJustChecked)
        XCTAssertEqual(MockURLProtocol.requestCount, 1, "the second open is served from cache")
    }

    func testCacheExpiresAfterTTL() async {
        MockURLProtocol.stub(statusCode: 200, body: "<h1>Product Designer</h1>")
        let clock = MutableClock()
        let cache = FreshnessCache(clock: clock.read)
        let sut = checker(cache: cache, ttl: 900)

        _ = await sut.check(jobURL)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)

        clock.now = clock.now.addingTimeInterval(901)   // past the TTL
        _ = await sut.check(jobURL)
        XCTAssertEqual(MockURLProtocol.requestCount, 2, "an expired entry re-fetches")
    }

    func testTransientFailureIsNotCached() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let sut = checker()

        let first = await sut.check(jobURL)
        XCTAssertEqual(first, .couldNotCheck)

        MockURLProtocol.stub(statusCode: 200, body: "<h1>Product Designer</h1>")
        let second = await sut.check(jobURL)
        XCTAssertEqual(second, .liveJustChecked, "a couldNotCheck must not stick for the TTL")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testCacheIsLRUCapped() async {
        let cache = FreshnessCache(capacity: 2)
        for i in 0..<3 {
            await cache.store(.liveJustChecked, for: URL(string: "https://x/\(i)")!)
        }
        let count = await cache.count
        XCTAssertEqual(count, 2, "oldest entry evicted at capacity")
        let evicted = await cache.value(for: URL(string: "https://x/0")!, ttl: 999)
        XCTAssertNil(evicted)
    }

    // MARK: Wi-Fi-only

    func testWifiOnlyOnCellularSkipsTheRequest() async {
        MockURLProtocol.stub(statusCode: 200, body: "<h1>Product Designer</h1>")
        let sut = checker(cellular: true)

        let status = await sut.check(jobURL, wifiOnly: true)

        XCTAssertEqual(status, .skippedOnCellular)
        XCTAssertEqual(MockURLProtocol.requestCount, 0, "no metered fetch when held to Wi-Fi")
    }

    func testWifiOnlyOffStillChecksOnCellular() async {
        MockURLProtocol.stub(statusCode: 200, body: "<h1>Product Designer</h1>")
        let sut = checker(cellular: true)

        let status = await sut.check(jobURL, wifiOnly: false)

        XCTAssertEqual(status, .liveJustChecked)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testCheckNowOverridesBothCacheAndCellular() async {
        MockURLProtocol.stub(statusCode: 200, body: "<h1>Product Designer</h1>")
        let cache = FreshnessCache()
        let sut = checker(cache: cache, cellular: true)

        // Seed the cache with a hit.
        await cache.store(.mayHaveClosed, for: jobURL)

        let forced = await sut.check(jobURL, wifiOnly: true, forceNow: true)
        XCTAssertEqual(forced, .liveJustChecked, "forceNow ignores the cache and the cellular guard")
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    // MARK: setting default

    func testWiFiOnlySettingDefaultsOn() {
        let suite = "test.wifiOnly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.checkLinksOnWiFiOnly, "on by default")

        settings.checkLinksOnWiFiOnly = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.checkLinksOnWiFiOnly, "the choice persists")
    }
}
