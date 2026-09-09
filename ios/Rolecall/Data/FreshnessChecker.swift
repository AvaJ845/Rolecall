import Foundation
import Network

/// The on-device liveness check. When the reader opens a role, Rolecall fetches the
/// posting URL itself, follows redirects, and decides whether the job still looks open —
/// so a designer never taps through to a dead link. No server sees the request.
///
/// Results are cached in an in-memory `FreshnessCache` (≈15 min TTL, LRU-capped), so
/// reopening a role does not re-fetch; and when "check links on Wi-Fi only" is on and
/// the path is cellular the check short-circuits to `.skippedOnCellular` instead of
/// spending metered data the reader didn't ask for.
struct FreshnessChecker {

    enum Status: Equatable {
        /// 2xx and the page still looks like the posting.
        case liveJustChecked
        /// 404/410, bounced to a careers index, or the body says it has closed.
        case mayHaveClosed
        /// Offline, timed out, or an ambiguous response — say nothing misleading.
        case couldNotCheck
        /// Not checked on purpose: the reader is on cellular and asked to hold checks
        /// to Wi-Fi. Distinct from `.couldNotCheck` so the UI can offer "Check now".
        case skippedOnCellular
    }

    /// Phrases an ATS puts on a pulled posting.
    static let deadBodyHints = [
        "no longer accepting applications",
        "no longer accepting application",
        "this job is no longer",
        "this position is no longer",
        "position has been filled",
        "job not found",
        "the job you are looking for",
        "posting is no longer available",
        "role has been filled",
    ]

    /// Path shapes an ATS redirects a closed role to (the careers index).
    static let indexPathHints = ["/jobs", "/careers", "/job-board", "/postings", "/openings", "/search"]

    static let defaultTTL: TimeInterval = 15 * 60

    private let session: URLSession
    private let cache: FreshnessCache
    private let ttl: TimeInterval
    private let isCellular: @Sendable () async -> Bool

    init(session: URLSession = .shared,
         cache: FreshnessCache = .shared,
         ttl: TimeInterval = FreshnessChecker.defaultTTL,
         isCellular: @escaping @Sendable () async -> Bool = { await NetworkStatus.shared.onCellular() }) {
        self.session = session
        self.cache = cache
        self.ttl = ttl
        self.isCellular = isCellular
    }

    /// Test seam so `MockURLProtocol` can be injected without touching the network.
    static func ephemeral(protocolClasses: [AnyClass],
                          cache: FreshnessCache = FreshnessCache(),
                          ttl: TimeInterval = FreshnessChecker.defaultTTL,
                          isCellular: @escaping @Sendable () async -> Bool = { false }) -> FreshnessChecker {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return FreshnessChecker(session: URLSession(configuration: config),
                                cache: cache, ttl: ttl, isCellular: isCellular)
    }

    /// - Parameters:
    ///   - wifiOnly: hold the check to Wi-Fi — on a cellular path, return `.skippedOnCellular`.
    ///   - forceNow: ignore both the cache and `wifiOnly` (the "Check now" button).
    func check(_ url: URL, wifiOnly: Bool = false, forceNow: Bool = false) async -> Status {
        if !forceNow, let cached = await cache.value(for: url, ttl: ttl) {
            return cached
        }
        if !forceNow, wifiOnly, await isCellular() {
            return .skippedOnCellular
        }
        let status = await fetchAndClassify(url)
        // Only cache a definitive verdict; a transient failure must not stick for the TTL.
        if status == .liveJustChecked || status == .mayHaveClosed {
            await cache.store(status, for: url)
        }
        return status
    }

    private func fetchAndClassify(_ url: URL) async -> Status {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        // A realistic Safari UA, on purpose: (1) many corporate career hosts sit behind
        // Cloudflare and 403 an unknown agent — that would surface as a false
        // "may have closed"; (2) it keeps the reader's use of Rolecall from being
        // announced to every employer whose posting they open.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        // A liveness probe, not a page load — never attach stored cookies.
        request.httpShouldHandleCookies = false

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .couldNotCheck }
            return Self.classify(
                statusCode: http.statusCode,
                finalURL: http.url ?? url,
                requestedURL: url,
                body: String(decoding: data.prefix(200_000), as: UTF8.self)
            )
        } catch {
            return .couldNotCheck
        }
    }

    /// Pure classification, extracted so it is exhaustively unit-testable.
    static func classify(statusCode: Int, finalURL: URL, requestedURL: URL, body: String) -> Status {
        if statusCode == 404 || statusCode == 410 { return .mayHaveClosed }

        let haystack = body.lowercased()
        if deadBodyHints.contains(where: haystack.contains) { return .mayHaveClosed }

        if redirectLostThePosting(finalURL: finalURL, requestedURL: requestedURL) {
            return .mayHaveClosed
        }

        if (200..<400).contains(statusCode) { return .liveJustChecked }
        return .couldNotCheck
    }

    /// True when a redirect dropped the reader on something that is no longer the
    /// posting: the identifying tail of the original URL is gone, and we landed either
    /// somewhere shallow or on a careers-index-shaped path.
    static func redirectLostThePosting(finalURL: URL, requestedURL: URL) -> Bool {
        guard finalURL.absoluteString != requestedURL.absoluteString else { return false }

        let finalString = finalURL.absoluteString.lowercased()
        let requestedSegments = requestedURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // Posting id survived the redirect (canonicalisation, host move) — still live.
        if let jobID = requestedSegments.last, jobID.count >= 3,
           finalString.contains(jobID.lowercased()) {
            return false
        }
        if let query = finalURL.query, query.rangeOfCharacter(from: .decimalDigits) != nil {
            return false
        }

        let finalSegments = finalURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let indexShaped = indexPathHints.contains(where: finalString.contains)
        return finalSegments.count <= 2 || indexShaped
    }
}
