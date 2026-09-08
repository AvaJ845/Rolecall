import Foundation

/// The on-device liveness check. When the reader opens a role, Rolecall fetches the
/// posting URL itself, follows redirects, and decides whether the job still looks open —
/// so a designer never taps through to a dead link. No server sees the request.
struct FreshnessChecker {

    enum Status: Equatable {
        /// 2xx and the page still looks like the posting.
        case liveJustChecked
        /// 404/410, bounced to a careers index, or the body says it has closed.
        case mayHaveClosed
        /// Offline, timed out, or an ambiguous response — say nothing misleading.
        case couldNotCheck
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

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Test seam so `MockURLProtocol` can be injected without touching the network.
    static func ephemeral(protocolClasses: [AnyClass]) -> FreshnessChecker {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return FreshnessChecker(session: URLSession(configuration: config))
    }

    func check(_ url: URL) async -> Status {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Rolecall/1.0 (+https://rolecall.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

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
