import Foundation

/// A named search the reader keeps — a filter + query pair, optionally with alerts.
/// On device only (App Group UserDefaults). Free tier keeps one; Rolecall Plus keeps
/// as many as you like and can turn alerts on.
struct SavedSearch: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var filter: RoleFilter
    var query: String
    /// Alert when a new matching role appears (Plus only; ignored otherwise).
    var notify: Bool
    let createdAt: Date
    /// The last time an alert for this search was posted — the window for "new" roles.
    var lastNotifiedAt: Date?

    init(name: String, filter: RoleFilter, query: String = "", notify: Bool = false) {
        self.id = UUID()
        self.name = name
        self.filter = filter
        self.query = query
        self.notify = notify
        self.createdAt = Date()
        self.lastNotifiedAt = nil
    }

    func matches(_ role: Role) -> Bool {
        guard filter.matches(role) else { return false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return role.company.localizedCaseInsensitiveContains(q)
            || role.title.localizedCaseInsensitiveContains(q)
    }

    /// Roles in `board` that match and first appeared since the last alert (or since the
    /// search was created, for the first alert).
    func newRoles(in board: Board, now: Date = Date()) -> [Role] {
        let since = lastNotifiedAt ?? createdAt
        return board.roles.filter { $0.firstSeen > since && matches($0) }
    }

    func matchCount(in board: Board) -> Int {
        board.roles.lazy.filter(matches).count
    }
}

@MainActor
final class SavedSearches: ObservableObject {

    @Published private(set) var searches: [SavedSearch]

    /// The free tier keeps exactly one saved search. Adding a second requires Plus.
    static let freeLimit = 1

    private let defaults: UserDefaults
    private let key = "savedSearches.v1"

    init(defaults: UserDefaults = SharedContainer.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            self.searches = decoded
        } else {
            self.searches = []
        }
    }

    var canAddWithoutPlus: Bool { searches.count < Self.freeLimit }

    func add(_ search: SavedSearch) {
        searches.append(search)
        persist()
    }

    func update(_ search: SavedSearch) {
        guard let i = searches.firstIndex(where: { $0.id == search.id }) else { return }
        searches[i] = search
        persist()
    }

    func remove(_ search: SavedSearch) {
        searches.removeAll { $0.id == search.id }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        searches.remove(atOffsets: offsets)
        persist()
    }

    /// Called after an alert fires for a search: advance its window.
    func markNotified(_ id: UUID, at date: Date = Date()) {
        guard let i = searches.firstIndex(where: { $0.id == id }) else { return }
        searches[i].lastNotifiedAt = date
        persist()
    }

    /// Settings → "Clear all my data".
    func wipeAll() {
        searches = []
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(searches) else { return }
        defaults.set(data, forKey: key)
    }
}
