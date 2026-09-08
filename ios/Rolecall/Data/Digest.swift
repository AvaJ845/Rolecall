import Foundation
import UserNotifications
import BackgroundTasks

/// Two opt-in, on-device digests: a morning read (roles listed in the last day) and a
/// weekly recap. Both are computed from the local board — no server, no push. If there's
/// nothing to say, nothing fires: the app never nags.
enum Digest {

    static let refreshTaskID = "com.avaresearch.rolecall.refresh"
    private static let morningID = "rolecall.digest.morning"
    private static let weeklyID = "rolecall.digest.weekly"
    private static func alertID(_ id: UUID) -> String { "rolecall.search.\(id.uuidString)" }

    // MARK: permission

    /// Returns true if notifications are (now) authorised. Called when a toggle flips on.
    @MainActor
    static func ensureAuthorised() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    // MARK: scheduling

    /// Rebuild the pending digest + saved-search-alert notifications from the current
    /// board + settings. Safe to call often (on background, on toggle change, at the end
    /// of a bg refresh). Saved-search alerts only fire when `isPlus` is true.
    @MainActor
    static func reschedule(board: Board, tracked: TrackedRoles, settings: AppSettings,
                           searches: SavedSearches? = nil, isPlus: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningID, weeklyID])

        let alerting = (isPlus ? searches?.searches.filter(\.notify) : nil) ?? []
        let wantDigests = settings.morningRead || settings.weeklyRecap

        guard wantDigests || !alerting.isEmpty else { return }
        guard await ensureAuthorised() else { return }

        if !alerting.isEmpty, let searches {
            await scheduleSearchAlerts(alerting, board: board, searches: searches, center: center)
        }
        guard wantDigests else { return }

        let designFamilies = RoleFilter.designFamilies
        let now = Date()
        let cal = Calendar.current

        if settings.morningRead {
            let dayAgo = now.addingTimeInterval(-86_400)
            let fresh = board.roles.filter {
                designFamilies.contains($0.family) && !$0.looksNonUS && $0.firstSeen > dayAgo
            }.count
            if fresh > 0, let trigger = morningTrigger(cal: cal, now: now) {
                add(center, id: morningID,
                    title: "\(fresh) new \(fresh == 1 ? "role" : "roles")",
                    body: "Listed since yesterday — all verified live.",
                    trigger: trigger)
            }
        }

        if settings.weeklyRecap {
            let weekAgo = now.addingTimeInterval(-7 * 86_400)
            let newThisWeek = board.roles.filter {
                designFamilies.contains($0.family) && !$0.looksNonUS && $0.firstSeen > weekAgo
            }.count
            if newThisWeek > 0, let trigger = weeklyTrigger(cal: cal) {
                var body = "\(newThisWeek) new \(newThisWeek == 1 ? "role" : "roles") this week."
                if tracked.savedCount > 0 { body += " \(tracked.savedCount) saved." }
                if tracked.appliedCount > 0 { body += " \(tracked.appliedCount) in progress." }
                add(center, id: weeklyID, title: "This week on Rolecall", body: body, trigger: trigger)
            }
        }
    }

    /// One notification per saved search that has genuinely new matching roles. Fires
    /// almost immediately (the board was just refreshed); if nothing's new, nothing fires.
    @MainActor
    private static func scheduleSearchAlerts(_ list: [SavedSearch], board: Board,
                                             searches: SavedSearches,
                                             center: UNUserNotificationCenter) async {
        let now = Date()
        for search in list {
            let new = search.newRoles(in: board, now: now)
            guard !new.isEmpty else { continue }
            let n = new.count
            let lead = new.prefix(2).map { "\($0.title) at \($0.company)" }.joined(separator: ", ")
            add(center, id: alertID(search.id),
                title: "\(n) new \(n == 1 ? "role" : "roles") · \(search.name)",
                body: n <= 2 ? lead : "\(lead), and \(n - 2) more.",
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
            searches.markNotified(search.id, at: now)
        }
    }

    private static func add(_ center: UNUserNotificationCenter, id: String,
                            title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Next 8:00 local time (tomorrow if today's has passed).
    private static func morningTrigger(cal: Calendar, now: Date) -> UNCalendarNotificationTrigger? {
        var comps = DateComponents(); comps.hour = 8; comps.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    }

    /// Monday 8:00 local time, repeating.
    private static func weeklyTrigger(cal: Calendar) -> UNCalendarNotificationTrigger? {
        var comps = DateComponents(); comps.weekday = 2; comps.hour = 8; comps.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    }

    // MARK: background refresh

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Does the background task have anything to do? Digests are on, or a Plus subscriber
    /// has at least one notifying saved search.
    @MainActor
    static func hasWorkToDo(settings: AppSettings, searches: SavedSearches, isPlus: Bool) -> Bool {
        let hasAlerts = isPlus && searches.searches.contains(where: \.notify)
        return settings.morningRead || settings.weeklyRecap || hasAlerts
    }

    /// The body of the background-refresh task: pull a fresh board, recompute the
    /// digests, and queue the next refresh.
    ///
    /// P0-15: no `Store()` / StoreKit init and no `Task.sleep`. `isPlus` is the plain Bool
    /// `Store.refreshEntitlements()` last cached in the App Group defaults. `AppSettings`
    /// and `SavedSearches` stay — cheap `UserDefaults` reads. Worst case of a stale Bool:
    /// a lapsed subscriber gets one extra alert cycle, a new one waits one cycle.
    @MainActor
    static func runBackgroundRefresh() async {
        scheduleBackgroundRefresh()
        let settings = AppSettings()
        let searches = SavedSearches()
        let isPlus = SharedContainer.lastKnownIsPlus
        guard hasWorkToDo(settings: settings, searches: searches, isPlus: isPlus) else { return }
        let store = BoardStore()
        await store.refresh()
        await reschedule(board: store.board, tracked: TrackedRoles(), settings: settings,
                         searches: searches, isPlus: isPlus)
    }
}
