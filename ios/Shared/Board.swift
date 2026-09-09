import Foundation

/// The ruleset that produced a board snapshot — the engine writes it into `board.json`'s
/// `meta` block. Optional and fully defaulted so snapshots from before `meta` existed
/// still decode. Nothing in the UI depends on it yet; it is for debuggability and future
/// migrations. The signature covers it automatically.
struct BoardMeta: Codable, Hashable {
    var classifierVersion: String?
    var includePM: Bool?
    var vertical: String?

    enum CodingKeys: String, CodingKey {
        case classifierVersion = "classifier_version"
        case includePM = "include_pm"
        case vertical
    }
}

/// A whole board snapshot — the file the engine writes to `data/board.json` and the
/// app bundles and later fetches from `BoardSource.remoteURL`.
struct Board: Codable, Hashable {

    /// Unix epoch seconds when the engine generated this snapshot.
    let generatedUTC: Date
    let count: Int
    let roles: [Role]
    /// Nil for snapshots written before the engine stamped `meta`.
    var meta: BoardMeta?

    enum CodingKeys: String, CodingKey {
        case generatedUTC = "generated_utc"
        case count, roles, meta
    }

    init(generatedUTC: Date, count: Int, roles: [Role], meta: BoardMeta? = nil) {
        self.generatedUTC = generatedUTC
        self.count = count
        self.roles = roles
        self.meta = meta
    }

    static let empty = Board(generatedUTC: .distantPast, count: 0, roles: [])

    static func decode(from data: Data) throws -> Board {
        try Role.makeDecoder().decode(Board.self, from: data)
    }

    /// `pretty` is for the rare case a human reads the output. The on-device cache file
    /// (`SharedContainer.writeBoard`) is machine-read only, so it is written compact —
    /// pretty-printing a multi-thousand-role board is pure main-thread/disk overhead.
    func encoded(pretty: Bool = false) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try e.encode(self)
    }

    /// De-duplicated union of two snapshots, keyed by posting URL, preferring the entry
    /// with the more recent `freshnessDate`. Used to merge a freshly fetched remote board
    /// over the bundled one without ever dropping a role the newer snapshot still lists.
    func merging(_ other: Board) -> Board {
        let newer = other.generatedUTC >= generatedUTC ? other : self
        let older = other.generatedUTC >= generatedUTC ? self : other

        // The newer snapshot is authoritative about which roles are still live: a role the
        // engine dropped must disappear. So the newer set defines membership; the older
        // set only fills in a richer `lastVerified`/`firstSeen` where it has one.
        var byID = Dictionary(uniqueKeysWithValues: older.roles.map { ($0.id, $0) })
        var merged: [Role] = []
        merged.reserveCapacity(newer.roles.count)
        for role in newer.roles {
            if let prior = byID[role.id] {
                merged.append(Role(
                    company: role.company,
                    title: role.title,
                    family: role.family,
                    location: role.location,
                    remote: role.remote,
                    url: role.url,
                    firstSeen: min(role.firstSeen, prior.firstSeen),
                    lastVerified: [role.lastVerified, prior.lastVerified].compactMap { $0 }.max()
                ))
            } else {
                merged.append(role)
            }
            byID[role.id] = nil
        }
        return Board(generatedUTC: newer.generatedUTC, count: merged.count, roles: merged,
                     meta: newer.meta)
    }

    /// The roles Rolecall will actually show: `https` only — an `http:` or `javascript:`
    /// "Apply" link on a trust surface is a phishing vector — and de-duplicated by id.
    /// Applied to every snapshot before it reaches the UI.
    func sanitized() -> Board {
        var seen = Set<String>()
        let safe = roles.filter { role in
            guard role.url.scheme?.lowercased() == "https" else { return false }
            return seen.insert(role.id).inserted
        }
        return Board(generatedUTC: generatedUTC, count: safe.count, roles: safe, meta: meta)
    }

    /// A fetched remote snapshot must clear this bar before it may replace what the app
    /// already trusts: it parsed, it is strictly newer, it is not empty, and it has not
    /// lost more than half its roles (a sign of a truncated or corrupted publish).
    /// A last sanity gate *after* the Ed25519 signature has already been verified — it
    /// bounds the damage of a validly-signed but broken publish (a truncated or half-empty
    /// board), never a substitute for the signature.
    func isPlausibleReplacement(for current: Board) -> Bool {
        generatedUTC > current.generatedUTC
            && !roles.isEmpty
            && roles.count * 2 >= current.roles.count
    }
}
