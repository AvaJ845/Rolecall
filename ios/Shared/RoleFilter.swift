import Foundation

/// The reader's current filter. Lives only in memory — there is nothing to persist and
/// nothing to sync.
struct RoleFilter: Equatable {
    /// Empty means "every family".
    var families: Set<RoleFamily> = []
    var remoteOnly: Bool = false

    var isActive: Bool { !families.isEmpty || remoteOnly }

    func matches(_ role: Role) -> Bool {
        if remoteOnly && !role.isRemote { return false }
        if !families.isEmpty && !families.contains(role.family) { return false }
        return true
    }

    var summary: String {
        var parts: [String] = []
        if !families.isEmpty {
            parts.append(families
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.shortLabel)
                .joined(separator: ", "))
        }
        if remoteOnly { parts.append("Remote only") }
        return parts.isEmpty ? "All roles" : parts.joined(separator: " · ")
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
