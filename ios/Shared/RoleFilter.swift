import Foundation

/// The reader's current filter. Persisted on device only, so the app opens the way they
/// left it — nothing here is synced or transmitted.
struct RoleFilter: Equatable, Codable {

    /// The families Rolecall leads with: the product-design vertical proper. Product
    /// Management is classified by the engine but is **off by default** — it outnumbers
    /// design on the board, and burying it keeps the "for designers" identity (and the
    /// Apple design-editorial story) clean. The reader can switch it on in the filter.
    static let designFamilies: Set<RoleFamily> = [.design, .designEng, .research]

    var families: Set<RoleFamily> = RoleFilter.designFamilies
    var remoteOnly: Bool = false
    /// On by default — the board covers the US + US-remote, and showing a Singapore or
    /// London role at a US company breaks that promise on sight.
    var usAndRemoteOnly: Bool = true

    /// True when the filter differs from the default view.
    var isActive: Bool {
        families != Self.designFamilies || remoteOnly || !usAndRemoteOnly
    }

    func matches(_ role: Role) -> Bool {
        if remoteOnly && !role.isRemote { return false }
        if usAndRemoteOnly && role.looksNonUS { return false }
        return families.contains(role.family)
    }

    var summary: String {
        var parts: [String] = []
        if families.isEmpty {
            parts.append("No families")
        } else if families != Self.designFamilies {
            parts.append(families
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.shortLabel)
                .joined(separator: ", "))
        } else {
            parts.append("Design roles")
        }
        if remoteOnly { parts.append("Remote only") }
        if !usAndRemoteOnly { parts.append("Worldwide") }
        return parts.joined(separator: " · ")
    }

    // MARK: on-device persistence

    private static let storeKey = "filter.v1"

    static func loadPersisted(_ defaults: UserDefaults = SharedContainer.defaults) -> RoleFilter {
        guard let data = defaults.data(forKey: storeKey),
              let filter = try? JSONDecoder().decode(RoleFilter.self, from: data)
        else { return RoleFilter() }
        return filter
    }

    func persist(_ defaults: UserDefaults = SharedContainer.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storeKey)
    }
}

/// One dated group in the list.
struct RoleSection: Identifiable {
    enum Band: String, CaseIterable {
        case today = "New today"
        case week = "This week"
        case earlier = "Earlier"
    }
    let band: Band
    let roles: [Role]
    var id: String { band.rawValue }
}

enum RoleSectioning {

    /// Filter, sort newest-first, and bucket into New today / This week / Earlier by
    /// each role's freshness date.
    static func sections(from roles: [Role],
                         filter: RoleFilter,
                         now: Date = Date(),
                         calendar: Calendar = .current) -> [RoleSection] {
        let visible = roles
            .filter(filter.matches)
            .sorted { $0.freshnessDate > $1.freshnessDate }

        let startOfToday = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        var buckets: [RoleSection.Band: [Role]] = [:]
        for role in visible {
            let band: RoleSection.Band
            if role.freshnessDate >= startOfToday {
                band = .today
            } else if role.freshnessDate >= weekAgo {
                band = .week
            } else {
                band = .earlier
            }
            buckets[band, default: []].append(role)
        }

        return RoleSection.Band.allCases.compactMap { band in
            guard let roles = buckets[band], !roles.isEmpty else { return nil }
            return RoleSection(band: band, roles: roles)
        }
    }
}
