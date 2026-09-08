import Foundation

/// Where an application stands. The reader moves it along by hand — Rolecall never infers
/// a stage; it just keeps the note for them.
enum ApplicationStage: String, Codable, CaseIterable, Identifiable {
    case applied
    case recruiterScreen
    case hiringManager
    case interviewing
    case finalRound
    case offer
    case rejected
    case withdrew

    var id: String { rawValue }

    var label: String {
        switch self {
        case .applied: return "Applied"
        case .recruiterScreen: return "Recruiter screen"
        case .hiringManager: return "Hiring manager"
        case .interviewing: return "Interviewing"
        case .finalRound: return "Final round"
        case .offer: return "Offer"
        case .rejected: return "Rejected"
        case .withdrew: return "Withdrew"
        }
    }

    /// True for stages that end the process — used to gray the entry out in reports.
    var isClosed: Bool { self == .rejected || self == .withdrew }
}

/// The reader's record of one application: when they applied, where it stands now, and
/// an optional private note.
struct Application: Codable, Equatable, Hashable {
    var appliedOn: Date
    var stage: ApplicationStage
    var updatedOn: Date
    var note: String

    init(appliedOn: Date = Date(), stage: ApplicationStage = .applied, note: String = "") {
        self.appliedOn = appliedOn
        self.stage = stage
        self.updatedOn = appliedOn
        self.note = note
    }
}

/// What the reader has done with a role. On-device only — there is no account and
/// nothing to sync. A role with no entry here is untouched.
enum RoleStatus: Codable, Equatable, Hashable {
    case saved
    case applied(Application)
    case notInterested

    var isSaved: Bool { self == .saved }
    var isApplied: Bool { application != nil }
    var isHidden: Bool { self == .notInterested }

    var application: Application? {
        if case let .applied(app) = self { return app }
        return nil
    }
    var appliedDate: Date? { application?.appliedOn }
}

/// The reader's private record of their search: which roles they saved, which they
/// applied to (and where each stands), which they never want to see again. Plus the
/// timestamp of their last visit, so the list can quietly mark what's new.
///
/// Persisted as one small JSON blob in the App Group container. No network. Keys are
/// role URLs — stable across every ATS.
@MainActor
final class TrackedRoles: ObservableObject {

    @Published private(set) var states: [String: RoleStatus]
    /// When the app was last foregrounded — the cutoff for "new since you last looked".
    @Published private(set) var lastVisit: Date

    private let defaults: UserDefaults
    private let statesKey = "tracked.states.v1"
    private let visitKey = "tracked.lastVisit.v1"

    init(defaults: UserDefaults = SharedContainer.defaults) {
        self.defaults = defaults
        self.states = Self.load(from: defaults, key: statesKey)
        let stored = defaults.object(forKey: visitKey) as? Double
        self.lastVisit = stored.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
    }

    // MARK: reads

    func status(for role: Role) -> RoleStatus? { states[role.id] }
    func application(for role: Role) -> Application? { states[role.id]?.application }

    var savedCount: Int { states.values.filter(\.isSaved).count }
    var appliedCount: Int { states.values.filter(\.isApplied).count }
    var hasActivity: Bool { states.values.contains { $0.isSaved || $0.isApplied } }

    func isNew(_ role: Role) -> Bool {
        lastVisit > .distantPast && role.firstSeen > lastVisit
    }

    func roles(in board: Board, matching predicate: (RoleStatus) -> Bool) -> [Role] {
        board.roles.filter { role in
            guard let s = states[role.id] else { return false }
            return predicate(s)
        }
    }

    /// Every application the reader is tracking, even for roles that have since left the
    /// board — the report in Settings needs them all. Newest activity first.
    func allApplications(in board: Board) -> [(role: Role, application: Application)] {
        let byID = Dictionary(uniqueKeysWithValues: board.roles.map { ($0.id, $0) })
        return states.compactMap { id, status -> (Role, Application)? in
            guard case let .applied(app) = status else { return nil }
            guard let role = byID[id] ?? Self.placeholderRole(id: id) else { return nil }
            return (role, app)
        }
        .sorted { $0.1.updatedOn > $1.1.updatedOn }
    }

    // MARK: writes

    func toggleSaved(_ role: Role) {
        states[role.id] = states[role.id]?.isSaved == true ? nil : .saved
        persistStates()
    }

    func markApplied(_ role: Role, on date: Date = Date()) {
        if states[role.id]?.isApplied == true { return }
        states[role.id] = .applied(Application(appliedOn: date))
        persistStates()
    }

    func updateApplication(for role: Role, _ mutate: (inout Application) -> Void) {
        guard case var .applied(app) = states[role.id] else { return }
        mutate(&app)
        app.updatedOn = Date()
        states[role.id] = .applied(app)
        persistStates()
    }

    func unmarkApplied(_ role: Role) {
        if states[role.id]?.isApplied == true { states[role.id] = nil }
        persistStates()
    }

    func setNotInterested(_ role: Role) {
        states[role.id] = .notInterested
        persistStates()
    }

    func clear(_ role: Role) {
        states[role.id] = nil
        persistStates()
    }

    /// Settings → "Clear my data". Wipes everything this store owns.
    func wipeAll() {
        states = [:]
        lastVisit = .distantPast
        defaults.removeObject(forKey: statesKey)
        defaults.removeObject(forKey: visitKey)
    }

    func recordVisit(_ date: Date = Date()) {
        lastVisit = date
        defaults.set(date.timeIntervalSince1970, forKey: visitKey)
    }

    /// Keep the store bounded: drop saved / not-interested entries for roles that have
    /// left the board; keep applications for a year regardless.
    func prune(against board: Board, now: Date = Date()) {
        let live = Set(board.roles.map(\.id))
        let yearAgo = now.addingTimeInterval(-365 * 86400)
        states = states.filter { id, status in
            if live.contains(id) { return true }
            if case let .applied(app) = status { return app.updatedOn > yearAgo }
            return false
        }
        persistStates()
    }

    // MARK: persistence

    private func persistStates() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: statesKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [String: RoleStatus] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: RoleStatus].self, from: data)
        else { return [:] }
        return decoded
    }

    /// A stand-in Role for an application whose posting has left the board, so the
    /// Settings report can still show the company and title from the id we kept.
    private static func placeholderRole(id: String) -> Role? {
        guard let url = URL(string: id) else { return nil }
        return Role(company: url.host ?? "—", title: "Role no longer listed",
                    family: .design, location: nil, remote: nil, url: url,
                    firstSeen: .distantPast, lastVerified: nil)
    }
}
