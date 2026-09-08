import Foundation

/// One live posting, straight from a company's own ATS feed.
///
/// Field names mirror the engine's `export` contract in `engine/pipeline.py`:
/// `{company, title, family, location, remote, url, first_seen, last_verified}`.
/// Nothing here is derived on a server — the app reasons about freshness on device.
struct Role: Codable, Identifiable, Hashable {

    let company: String
    let title: String
    let family: RoleFamily
    let location: String?
    /// The engine may leave this `null` when the feed does not say. Absence is not "office".
    let remote: Bool?
    let url: URL
    /// Unix epoch seconds. When the engine first saw this posting in the company feed.
    let firstSeen: Date
    /// Unix epoch seconds. Last time the engine HTTP-verified the posting still looked
    /// live. `nil` until the engine's `verify` pass has reached it.
    let lastVerified: Date?

    enum CodingKeys: String, CodingKey {
        case company, title, family, location, remote, url
        case firstSeen = "first_seen"
        case lastVerified = "last_verified"
    }

    /// A stable identity for a posting: the ATS URL is unique per role across every
    /// supported provider (Greenhouse/Ashby/Lever/Workable).
    var id: String { url.absoluteString }

    /// The timestamp the freshness line is built from: the verify time when we have one,
    /// otherwise the first-seen time.
    var freshnessDate: Date { lastVerified ?? firstSeen }

    /// A human location line: the city/region, or "Remote", or both.
    var locationLine: String {
        let place = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (place, remote) {
        case let (p?, true) where !p.isEmpty: return "\(p) · Remote"
        case (_, true): return "Remote"
        case let (p?, _) where !p.isEmpty: return p
        default: return "Location not specified"
        }
    }

    var isRemote: Bool { remote == true }

    /// The board's promise is "one region you can actually cover" — the US, plus
    /// US-remote. A role whose location clearly names somewhere else is filtered out by
    /// default. Deliberately conservative: unknown / empty / US-looking all pass; only an
    /// explicit non-US place is dropped.
    var looksNonUS: Bool {
        guard !isRemote else { return false }
        let l = (location ?? "").lowercased()
        guard !l.isEmpty else { return false }
        if Self.usHints.contains(where: l.contains) { return false }
        return Self.nonUSHints.contains(where: l.contains)
    }

    private static let usHints: [String] = [
        "united states", "usa", "u.s", "remote", "anywhere",
        "san francisco", "new york", "nyc", "seattle", "austin", "chicago", "boston",
        "los angeles", "denver", "atlanta", "portland", "miami", "washington", "brooklyn",
    ]
    private static let nonUSHints: [String] = [
        "united kingdom", "england", "london", "canada", "toronto", "vancouver", "ontario",
        "germany", "berlin", "munich", "france", "paris", "netherlands", "amsterdam",
        "ireland", "dublin", "singapore", "australia", "sydney", "melbourne", "india",
        "bangalore", "bengaluru", "hyderabad", "israel", "tel aviv", "spain", "barcelona",
        "madrid", "poland", "warsaw", "brazil", "são paulo", "sao paulo", "japan", "tokyo",
        "milan", "italy", "rome", "sweden", "stockholm", "portugal", "lisbon", "mexico",
        "emea", "apac", "latam", "switzerland", "zurich", "denmark", "copenhagen",
        "norway", "oslo", "finland", "helsinki", "belgium", "brussels", "austria", "vienna",
    ]
}

extension Role {
    /// The decoder the app and the widget both use. Epoch seconds → `Date`.
    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
